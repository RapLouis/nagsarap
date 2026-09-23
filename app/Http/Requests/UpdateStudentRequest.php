<?php

namespace App\Http\Requests;

use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class UpdateStudentRequest extends FormRequest
{
    public function authorize(): bool
    {
        // Route is already behind the 'admin' middleware group; this is a second gate
        // in case the request ever reaches this class outside that group.
        return $this->user()?->role === 'admin';
    }

    public function rules(): array
    {
        /** @var \App\Models\Student $student */
        $student = $this->route('student');

        return [
            'firstname' => ['required', 'string', 'max:100'],
            'surname' => ['required', 'string', 'max:100'],
            'email' => [
                'required', 'email', 'max:255',
                Rule::unique('students', 'email')->ignore($student->student_id, 'student_id'),
            ],
            'student_number' => [
                'required', 'string', 'max:50',
                Rule::unique('students', 'student_number')->ignore($student->student_id, 'student_id'),
            ],
            'degree' => ['nullable', 'string', 'max:255'],
            'year_section' => ['nullable', 'string', 'max:100'],
        ];
    }
}