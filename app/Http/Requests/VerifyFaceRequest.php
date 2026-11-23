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
        $frame = [
            'file',
            'mimetypes:image/jpeg,image/jpg,image/png',
            'max:2048',
            'dimensions:min_width=320,min_height=240,max_width=1920,max_height=1920',
        ];

        return [
            'live_camera_frame' => ['required', ...$frame],
            'turn_peak_frame'   => ['required', ...$frame],
            'flash_frames'      => ['required', 'array', 'size:3'],
            'flash_frames.*'    => ['required', ...$frame],
            'challenge_nonce'   => ['required', 'string', 'size:40'],
            'camera_label'      => ['nullable', 'string', 'max:200'],
            'slot_index'        => ['nullable', 'integer', 'min:0', 'max:99'],
            'type'              => ['nullable', 'in:in,out'],
            'checkpoint_key'    => ['nullable', 'string', 'max:50', 'in:morning_time_in,morning_time_out,afternoon_time_in,afternoon_time_out'],
        ];
    }

    public function messages(): array
    {
        return [
            'live_camera_frame.required' => 'The live camera image is missing. Please try again.',
            'turn_peak_frame.required'   => 'The head turn image is missing. Please try again.',
            'flash_frames.required'      => 'The lighting check images are missing. Please try again.',
            'flash_frames.size'          => 'The lighting check was incomplete. Please try again.',
            'challenge_nonce.required'   => 'Your verification session is invalid. Please try again.',
            'challenge_nonce.size'       => 'Your verification session is invalid. Please try again.',
            'checkpoint_key.in'          => 'The selected attendance checkpoint is invalid.',
        ];
    }
}