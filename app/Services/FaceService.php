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
        $path = $file->getRealPath();

        if (
            !$path
            || !is_file($path)
        ) {
            throw new RuntimeException(
                'Unable to read the supplied image.'
            );
        }

        $bytes = file_get_contents(
            $path
        );

        if (
            $bytes === false
            || $bytes === ''
        ) {
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
        if ($bytes === '') {
            throw new RuntimeException(
                'The supplied image is empty.'
            );
        }

        try {
            $response = Http::timeout(30)
                ->retry(
                    2,
                    300,
                    throw: false
                )
                ->post(
                    $this->faceUrl(
                        '/extract-embedding'
                    ),
                    [
                        'image_base64' =>
                            $this->toDataUrl(
                                $bytes
                            ),
                    ]
                );
        } catch (\Throwable $e) {
            throw new RuntimeException(
                'Unable to connect to the biometric service.'
            );
        }

        if ($response->failed()) {
            throw new RuntimeException(
                $response->json('detail')
                    ?? $response->json('message')
                    ?? 'Biometric service rejected the image.'
            );
        }

        $embedding =
            $response->json(
                'embedding'
            );

        if (
            !is_array($embedding)
            || count($embedding) === 0
        ) {
            throw new RuntimeException(
                'Biometric service returned an invalid embedding.'
            );
        }

        foreach ($embedding as $value) {
            if (!is_numeric($value)) {
                throw new RuntimeException(
                    'Biometric service returned an invalid embedding.'
                );
            }
        }

        return array_map(
            'floatval',
            $embedding
        );
    }

    public function analyzeLivenessFrame(
        UploadedFile $frame
    ): array {
        $path =
            $frame->getRealPath();

        if (
            !$path
            || !is_file($path)
        ) {
            throw new RuntimeException(
                'Unable to read camera frame.'
            );
        }

        $bytes =
            file_get_contents(
                $path
            );

        if (
            $bytes === false
            || $bytes === ''
        ) {
            throw new RuntimeException(
                'Unable to read camera frame.'
            );
        }

        try {
            $response =
                Http::timeout(20)
                    ->post(
                        $this->faceUrl(
                            '/analyze-liveness-frame'
                        ),
                        [
                            'image_base64' =>
                                $this->toDataUrl(
                                    $bytes
                                ),
                        ]
                    );
        } catch (\Throwable $e) {
            throw new RuntimeException(
                'Unable to connect to the biometric service.'
            );
        }

        if ($response->failed()) {
            throw new RuntimeException(
                $response->json('detail')
                    ?? $response->json('message')
                    ?? 'Unable to analyze live face.'
            );
        }

        $result =
            $response->json();

        if (!is_array($result)) {
            throw new RuntimeException(
                'Invalid liveness response.'
            );
        }

        return $result;
    }

    public function verifyLiveness(
        UploadedFile $centerFrame,
        UploadedFile $blinkFrame,
        UploadedFile $turnedFrame,
        UploadedFile $smileFrame,
        UploadedFile $returnedFrame,
    ): array {
        try {
            $response =
                Http::timeout(60)
                    ->post(
                        $this->faceUrl(
                            '/verify-liveness'
                        ),
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
        } catch (\Throwable $e) {
            throw new RuntimeException(
                'Unable to connect to the biometric service.'
            );
        }

        if ($response->failed()) {
            throw new RuntimeException(
                $response->json('detail')
                    ?? $response->json('message')
                    ?? 'Liveness verification failed.'
            );
        }

        $data =
            $response->json();

        if (
            !is_array($data)
            || ($data['success'] ?? false)
                !== true
        ) {
            throw new RuntimeException(
                $data['detail']
                    ?? $data['message']
                    ?? 'Liveness verification failed.'
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
            || count($vecB) === 0
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

            if (
                !is_numeric($a)
                || !is_numeric($b)
            ) {
                return 0.0;
            }

            $a = (float) $a;
            $b = (float) $b;

            $dotProduct +=
                $a * $b;

            $normA +=
                $a ** 2;

            $normB +=
                $b ** 2;
        }

        if (
            $normA <= 0.0
            || $normB <= 0.0
        ) {
            return 0.0;
        }

        $similarity =
            $dotProduct
            / (
                sqrt($normA)
                * sqrt($normB)
            );

        return max(
            -1.0,
            min(
                1.0,
                $similarity
            )
        );
    }

    private function uploadedFileToDataUrl(
        UploadedFile $file
    ): string {
        $path =
            $file->getRealPath();

        if (
            !$path
            || !is_file($path)
        ) {
            throw new RuntimeException(
                'Unable to read a liveness frame.'
            );
        }

        $bytes =
            file_get_contents(
                $path
            );

        if (
            $bytes === false
            || $bytes === ''
        ) {
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
            . base64_encode(
                $bytes
            );
    }

    private function faceUrl(
        string $endpoint
    ): string {
        $baseUrl =
            config(
                'services.face.url'
            );

        if (
            !is_string($baseUrl)
            || trim($baseUrl) === ''
        ) {
            throw new RuntimeException(
                'Biometric service URL is not configured.'
            );
        }

        return rtrim(
            $baseUrl,
            '/'
        ) . '/' . ltrim(
            $endpoint,
            '/'
        );
    }
}