<?php

namespace App\Actions\Fortify;

use App\Models\Student;
use App\Models\User;
use App\Services\Form5VerificationService;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Facades\Validator;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;
use Laravel\Fortify\Contracts\CreatesNewUsers;

class CreateNewUser implements CreatesNewUsers
{
    protected Form5VerificationService $form5Service;

    public function __construct(Form5VerificationService $form5Service)
    {
        $this->form5Service = $form5Service;
    }

    /**
     * Validate and create a newly registered user with student profile & Form 5 verification.
     *
     * @param  array<string, mixed>  $input
     */
    public function create(array $input): User
    {
        // 1. Validate Form Inputs, Profile Photo, and Form 5 File
        Validator::make($input, [
            'student_number' => ['required', 'string', 'regex:/^\d{2}-\d{6}$/', Rule::unique(Student::class, 'student_number')],
            'surname'        => ['required', 'string', 'max:100'],
            'firstname'      => ['required', 'string', 'max:100'],
            'middlename'     => ['nullable', 'string', 'max:100'],
            'ext'            => ['nullable', 'string', 'max:10'],
            'email'          => ['required', 'string', 'email', 'max:255', Rule::unique(User::class, 'email')],
            'password'       => ['required', 'string', 'min:12', 'regex:/[0-9]/', 'regex:/[^A-Za-z0-9]/', 'confirmed'],
            'profile_photo'  => ['required', 'image', 'mimes:jpeg,png,jpg', 'max:10240'],
            'form_5'         => [
                'required', 
                'file', 
                'max:10240',
                'mimetypes:application/pdf,application/x-pdf,application/acrobat,applications/vnd.pdf,text/pdf,text/x-pdf,application/octet-stream'
            ],
        ])->validate();

        // 2. Save Files to Secure Private Disk
        $photoPath = $input['profile_photo']->store('profile_photos', 'private');
        $pdfPath = $input['form_5']->store('form_5_documents', 'private');
        $pdfAbsolutePath = Storage::disk('private')->path($pdfPath);

        // 3. Extract 512-D Embedding from Profile Photo via Python Microservice
        $photoBase64 = base64_encode(file_get_contents($input['profile_photo']->getRealPath()));
        $photoEmbedding = null;

        try {
            $http = Http::baseUrl(rtrim(config('face_verification.python_url'), '/'))->timeout((int) config('face_verification.python_timeout'));
            if ($token = config('face_verification.python_token')) {
                $http = $http->withHeader('X-Internal-Token', $token);
            }
            $response = $http->post('/extract-embedding', [
                'image_base64' => $photoBase64,
            ]);

            if ($response->successful()) {
                $photoEmbedding = $response->json()['embedding'];
            } else {
                // Fixed: Clean up from private disk instead of public
                Storage::disk('private')->delete($photoPath);
                Storage::disk('private')->delete($pdfPath);

                $detail = $response->json()['detail'] ?? 'No clear face detected in profile photo.';
                throw ValidationException::withMessages([
                    'profile_photo' => "Profile Photo Error: {$detail}",
                ]);
            }
        } catch (\Exception $e) {
            if ($e instanceof ValidationException) {
                throw $e;
            }

            // Fixed: Clean up from private disk instead of public
            Storage::disk('private')->delete($photoPath);
            Storage::disk('private')->delete($pdfPath);

            throw ValidationException::withMessages([
                'profile_photo' => 'Unable to connect to biometric service on port 5000.',
            ]);
        }

        // 4. Form 5 Document Verification
        $fullNameParts = array_filter([
            $input['firstname'],
            $input['middlename'] ?? null,
            $input['surname'],
            $input['ext'] ?? null,
        ]);
        $expectedFullName = implode(' ', $fullNameParts);

        $verificationResult = $this->form5Service->verifyAndExtract(
            $pdfAbsolutePath,
            $input['student_number'],
            $expectedFullName
        );

        if (!$verificationResult['is_verified']) {
            Storage::disk('private')->delete($photoPath);
            Storage::disk('private')->delete($pdfPath);

            $errorMessage = 'Form 5 verification failed. The name on the document does not match your inputted name. Kindly ensure that the name on your Form 5 matches the name you provided during registration.';
            if (!$verificationResult['is_latest_term']) {
                $errorMessage = 'The uploaded Form 5 is not valid for the current academic year/semester.';
            }

            throw ValidationException::withMessages([
                'form_5' => $errorMessage,
            ]);
        }

        // 5. Create Student Record (Model Mutators automatically clean and title-case names)
        $extractedData = $verificationResult['data'];

        $student = Student::create([
            'student_number'      => $input['student_number'],
            'surname'             => $input['surname'],
            'firstname'           => $input['firstname'],
            'middlename'          => $input['middlename'] ?? null,
            'ext'                 => $input['ext'] ?? null,
            'email'               => $input['email'],
            'face_photo_path'     => $photoPath,
            'form_5_path'         => $pdfPath,
            'face_embedding'      => $photoEmbedding,
            'degree'              => $extractedData['degree'] ?? null,
            'year_section'        => $extractedData['year_section'] ?? null,
            'semester'            => $extractedData['semester'] ?? null,
            'academic_year'       => $extractedData['academic_year'] ?? null,
            'verification_status' => 'pending_face_verification',
        ]);

        // 6. Create User Account Linked to Student Profile
        return User::create([
            'name'       => "{$student->firstname} {$student->surname}",
            'email'      => $input['email'],
            'password'   => Hash::make($input['password']),
            'student_id' => $student->student_id,
        ]);
    }
}