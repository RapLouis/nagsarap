<?php

namespace App\Services;

use App\Exceptions\BiometricServiceException;
use App\Models\Student;
use Illuminate\Http\Client\ConnectionException;
use Illuminate\Http\Client\PendingRequest;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Storage;
use Illuminate\Http\UploadedFile;

class BiometricService
{
    public function profileEmbeddingFromFile(UploadedFile $file): array
    {
        $data = $this->post('/extract-embedding', ['image_base64' => $this->fileToDataUrl($file)]);
        $embedding = $data['embedding'] ?? null;
        if (!is_array($embedding)) throw new BiometricServiceException('Biometric service returned an invalid embedding.');
        return array_map('floatval', $embedding);
    }

    public function analyzeLivenessFrame(UploadedFile $frame): array
    {
        $data = $this->post('/analyze-liveness-frame', ['image_base64' => $this->fileToDataUrl($frame)]);
        return is_array($data) ? $data : throw new BiometricServiceException('Invalid liveness response.');
    }

    public function verifyLiveness(string $direction, UploadedFile $frontal, UploadedFile $peak, ?UploadedFile $mid = null): array
    {
        $payload = [
            'direction' => $direction,
            'frontal_image_base64' => $this->fileToDataUrl($frontal),
            'peak_image_base64' => $this->fileToDataUrl($peak),
        ];
        if ($mid) $payload['mid_image_base64'] = $this->fileToDataUrl($mid);
        $data=$this->post('/verify-liveness',$payload);
        if (!array_key_exists('passed',$data)) throw new BiometricServiceException('Unexpected liveness response.');
        return $data;
    }

    /** Try both directions only when the first authoritative check says the direction was wrong. */
    public function verifyLivenessEitherDirection(UploadedFile $frontal, UploadedFile $peak, ?UploadedFile $mid = null): array
    {
        $first=$this->verifyLiveness('left',$frontal,$peak,$mid);
        if (($first['passed'] ?? false) === true || ($first['reason_code'] ?? null) !== 'turn_wrong_direction') return $first;
        return $this->verifyLiveness('right',$frontal,$peak,$mid);
    }

    public function profileEmbedding(Student $student): ?array
    {
        if (!$student->face_photo_path) return null;
        $disk=Storage::disk('private');
        $path=ltrim(str_replace(['/storage/','storage/'],'',$student->face_photo_path),'/');
        if (!$disk->exists($path)) return null;
        $key='face_profile_embedding:'.$student->student_id.':'.md5($path.'|'.$disk->lastModified($path));
        $cached=Cache::get($key); if (is_array($cached)) return $cached;
        try { $data=$this->post('/extract-embedding',['image_base64'=>base64_encode($disk->get($path))]); }
        catch (BiometricServiceException) { return null; }
        $embedding=$data['embedding']??null;
        if (!is_array($embedding)) return null;
        Cache::put($key,$embedding,now()->addDays(30));
        return $embedding;
    }

    public static function cosineSimilarity(array $a,array $b): float
    {
        if (!$a || count($a)!==count($b)) return 0.0;
        $dot=$na=$nb=0.0;
        foreach ($a as $i=>$v) { if (!is_numeric($v)||!isset($b[$i])||!is_numeric($b[$i])) return 0.0; $x=(float)$v; $y=(float)$b[$i]; $dot+=$x*$y; $na+=$x*$x; $nb+=$y*$y; }
        return ($na<=0.0||$nb<=0.0)?0.0:$dot/(sqrt($na)*sqrt($nb));
    }

    private function fileToDataUrl(UploadedFile $file): string
    {
        $bytes=$file->get(); if ($bytes==='') throw new BiometricServiceException('The supplied image is empty.');
        return 'data:image/jpeg;base64,'.base64_encode($bytes);
    }

    private function post(string $endpoint,array $payload): array
    {
        try { $response=$this->client()->post($endpoint,$payload); }
        catch (ConnectionException $e) { Log::error('Biometric service unreachable',['error'=>$e->getMessage()]); throw new BiometricServiceException('Biometric service unreachable.',0,$e); }
        if ($response->failed()) { throw new BiometricServiceException($response->json('detail') ?? 'Biometric service returned an error.'); }
        $data=$response->json(); if (!is_array($data)) throw new BiometricServiceException('Biometric service returned invalid JSON.');
        return $data;
    }

    private function client(): PendingRequest
    {
        $client=Http::baseUrl(rtrim(config('face_verification.python_url'),'/'))->connectTimeout(5)->timeout((int)config('face_verification.python_timeout'))->acceptJson();
        if ($token=config('face_verification.python_token')) $client=$client->withHeader('X-Internal-Token',$token);
        return $client;
    }
}
