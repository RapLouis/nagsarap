<?php

namespace App\Http\Controllers;

use App\Models\Student;
use App\Models\User;
use App\Services\Form5VerificationService;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Storage;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;
use Inertia\Inertia;
use Inertia\Response;

class StudentRegistrationController extends Controller
{
    public function __construct(
        protected Form5VerificationService $form5Service
    ) {}

    /**
     * Display the student registration form.
     */
    public function showRegistrationForm(): Response
    {
        return Inertia::render('auth/register');
    }

    /**
     * Process initial registration details, Form 5 OCR check,
     * live selfie storage, and biometric consent.
     */
    public function register(Request $request): RedirectResponse
    {
        // 1. Validate parameters
        $validated = $request->validate([
            'student_number'    => ['required', 'string', 'regex:/^\d{2}-\d{6}$/', Rule::unique(Student::class, 'student_number')],
            'surname'           => ['required', 'string', 'max:100'],
            'firstname'         => ['required', 'string', 'max:100'],
            'middlename'        => ['nullable', 'string', 'max:100'],
            'ext'               => ['nullable', 'string', 'max:10'],
            'email'             => ['required', 'string', 'email', 'max:255', Rule::unique(User::class, 'email')],
            'password'          => ['required', 'string', 'min:8', 'confirmed'],
            'profile_photo'     => ['required', 'file', 'image', 'mimes:jpeg,jpg,png', 'max:10240'],
            'form_5'            => [
                'required',
                'file',
                'max:10240',
                'mimetypes:application/pdf,application/x-pdf,application/acrobat,applications/vnd.pdf,text/pdf,text/x-pdf,application/octet-stream',
            ],
            'biometric_consent' => ['required', 'accepted'],
        ]);

        // 2. Store Live Selfie & Form 5 Document on Secure Private Disk
        $photoPath = $request->file('profile_photo')->store("reference_photos/{$validated['student_number']}", 'private');
        $pdfPath = $request->file('form_5')->store("form_5_documents/{$validated['student_number']}", 'private');
        $pdfAbsolutePath = Storage::disk('private')->path($pdfPath);

        // 3. Early Form 5 OCR Validation (Fail cheap before liveness execution)
        $fullNameParts = array_filter([
            $validated['firstname'],
            $validated['middlename'] ?? null,
            $validated['surname'],
            $validated['ext'] ?? null,
        ]);
        $expectedFullName = implode(' ', $fullNameParts);

        $verificationResult = $this->form5Service->verifyAndExtract(
            $pdfAbsolutePath,
            $validated['student_number'],
            $expectedFullName
        );

        if (! ($verificationResult['is_verified'] ?? false)) {
            Storage::disk('private')->delete($photoPath);
            Storage::disk('private')->delete($pdfPath);

            $errorMessage = 'Form 5 verification failed. The name on the document does not match your inputted name.';
            if (! ($verificationResult['is_latest_term'] ?? true)) {
                $errorMessage = 'The uploaded Form 5 is not valid for the current academic year/semester.';
            }

            throw ValidationException::withMessages([
                'form_5' => $errorMessage,
            ]);
        }

        $extractedData = $verificationResult['data'] ?? [];

        // 4. Create Student Account with status 'pending_face_verification'
        $student = Student::create([
            'student_number'       => $validated['student_number'],
            'surname'              => $validated['surname'],
            'firstname'            => $validated['firstname'],
            'middlename'           => $validated['middlename'] ?? null,
            'ext'                  => $validated['ext'] ?? null,
            'email'                => strtolower(trim($validated['email'])),
            'face_photo_path'      => $photoPath,
            'form_5_path'          => $pdfPath,
            'degree'               => $extractedData['degree'] ?? null,
            'year_section'         => $extractedData['year_section'] ?? null,
            'semester'             => $extractedData['semester'] ?? null,
            'academic_year'        => $extractedData['academic_year'] ?? null,
            'biometric_consent_at' => now(),
            'verification_status'  => 'pending_face_verification',
            'face_embedding'       => null,
        ]);

        // 5. Create Linked User & Authenticate Session
        $user = User::create([
            'name'       => "{$student->firstname} {$student->surname}",
            'email'      => strtolower(trim($validated['email'])),
            'password'   => Hash::make($validated['password']),
            'student_id' => $student->student_id,
        ]);

        Auth::login($user);

        return redirect()->route('register.verify-face');
    }
}