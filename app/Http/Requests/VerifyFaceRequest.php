<?php

namespace App\Http\Requests;

use Illuminate\Foundation\Http\FormRequest;

class VerifyFaceRequest extends FormRequest
{
    public function authorize(): bool
    {
        return $this->user() !== null;
    }

    public function rules(): array
    {
        // Frames come from a 640x480 canvas at JPEG quality ~0.85 (roughly 60-150 KB each).
        $frame = ['file', 'mimetypes:image/jpeg', 'max:2048', 'dimensions:min_width=320,min_height=240,max_width=1920,max_height=1920'];

        return [
            // Frontal frame. Same field name as before, so it is also matched to the profile photo.
            'live_camera_frame' => ['required', ...$frame],
            'turn_peak_frame' => ['required', ...$frame],
            'turn_mid_frame' => ['nullable', ...$frame],

            'challenge_nonce' => ['required', 'string', 'size:40'],

            // The browser also sends "direction", but it is deliberately not read:
            // the direction comes from the server-side challenge.
        ];
    }

    public function messages(): array
    {
        return [
            'live_camera_frame.required' => 'The camera image is missing. Please try again.',
            'turn_peak_frame.required' => 'The head-turn image is missing. Please try again.',
            'challenge_nonce.required' => 'Your verification session is invalid. Please try again.',
            'challenge_nonce.size' => 'Your verification session is invalid. Please try again.',
        ];
    }
}