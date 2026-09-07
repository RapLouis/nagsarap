<?php

namespace App\Services;

use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Http;
use RuntimeException;

class FaceService
{
    public function extractEmbeddingFromUploadedFile(
        UploadedFile $file
    ): array {
        $bytes = file_get_contents(
            $file->getRealPath()
        );

        if ($bytes === false) {
            throw new RuntimeException(
                'Unable to read the supplied image.'
            );
        }

        return $this->extractEmbeddingFromBytes(
            $bytes
        );
    }

    public function extractEmbeddingFromBytes(
        string $bytes
    ): array {
        $response = Http::timeout(20)->post(
            rtrim(
                config('services.face.url'),
                '/'
            ).'/extract-embedding',
            [
                'image_base64' =>
                    $this->toDataUrl($bytes),
            ]
        );

        if ($response->failed()) {
            throw new RuntimeException(
                $response->json('detail')
                    ?? 'Biometric service rejected the image.'
            );
        }

        $embedding =
            $response->json('embedding');

        if (
            !is_array($embedding)
            || count($embedding) === 0
        ) {
            throw new RuntimeException(
                'Biometric service returned an invalid embedding.'
            );
        }

        return $embedding;
    }

    public function verifyLiveness(
        UploadedFile $centerFrame,
        UploadedFile $blinkFrame,
        UploadedFile $turnedFrame,
        UploadedFile $smileFrame,
        UploadedFile $returnedFrame,
    ): array {
        $response = Http::timeout(45)->post(
            rtrim(
                config('services.face.url'),
                '/'
            ).'/verify-liveness',
            [
                'center_frame' =>
                    $this->uploadedFileToDataUrl(
                        $centerFrame
                    ),

                'blink_frame' =>
                    $this->uploadedFileToDataUrl(
                        $blinkFrame
                    ),

                'turned_frame' =>
                    $this->uploadedFileToDataUrl(
                        $turnedFrame
                    ),

                'smile_frame' =>
                    $this->uploadedFileToDataUrl(
                        $smileFrame
                    ),

                'returned_frame' =>
                    $this->uploadedFileToDataUrl(
                        $returnedFrame
                    ),
            ]
        );

        if ($response->failed()) {
            throw new RuntimeException(
                $response->json('detail')
                    ?? 'Liveness verification failed.'
            );
        }

        $data = $response->json();

        if (
            !is_array($data)
            || ($data['success'] ?? false)
                !== true
        ) {
            throw new RuntimeException(
                'Liveness verification failed.'
            );
        }

        return $data;
    }

    public function cosineSimilarity(
        array $vecA,
        array $vecB
    ): float {
        if (
            count($vecA) === 0
            || count($vecA)
                !== count($vecB)
        ) {
            return 0.0;
        }

        $dotProduct = 0.0;
        $normA = 0.0;
        $normB = 0.0;

        foreach ($vecA as $i => $a) {
            $b = $vecB[$i];

            $dotProduct += $a * $b;
            $normA += $a ** 2;
            $normB += $b ** 2;
        }

        if (
            $normA == 0.0
            || $normB == 0.0
        ) {
            return 0.0;
        }

        return $dotProduct
            / (
                sqrt($normA)
                * sqrt($normB)
            );
    }

    private function uploadedFileToDataUrl(
        UploadedFile $file
    ): string {
        $bytes = file_get_contents(
            $file->getRealPath()
        );

        if ($bytes === false) {
            throw new RuntimeException(
                'Unable to read a liveness frame.'
            );
        }

        return $this->toDataUrl(
            $bytes
        );
    }

    private function toDataUrl(
        string $bytes
    ): string {
        return 'data:image/jpeg;base64,'
            .base64_encode($bytes);
    }
}