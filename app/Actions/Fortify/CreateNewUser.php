<?php

namespace App\Actions\Fortify;

use App\Concerns\PasswordValidationRules;
use App\Models\Student;
use App\Models\User;
use App\Services\FaceService;
use App\Services\Form5VerificationService;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Facades\Validator;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;
use Laravel\Fortify\Contracts\CreatesNewUsers;
use RuntimeException;
use Throwable;

class CreateNewUser implements CreatesNewUsers
{
    use PasswordValidationRules;

    public function __construct(
        private readonly Form5VerificationService $form5Service,
        private readonly FaceService $faceService,
    ) {}

    /*
    |--------------------------------------------------------------------------
    | CREATE USER
    |--------------------------------------------------------------------------
    */

    public function create(array $input): User
    {
        /*
        |--------------------------------------------------------------------------
        | 1. VALIDATE REGISTRATION DATA
        |--------------------------------------------------------------------------
        */

        Validator::make(
            $input,
            [
                'student_number' => [
                    'required',
                    'string',
                    'max:20',

                    /*
                     * Format:
                     *
                     * 24-010342
                     *
                     * 24   = year
                     * 01   = college code
                     * 0342 = student sequence
                     */

                    'regex:/^\d{2}-\d{6}$/',

                    Rule::unique(
                        'students',
                        'student_number'
                    ),
                ],

                'surname' => [
                    'required',
                    'string',
                    'max:100',
                ],

                'firstname' => [
                    'required',
                    'string',
                    'max:100',
                ],

                'middlename' => [
                    'nullable',
                    'string',
                    'max:100',
                ],

                'ext' => [
                    'nullable',
                    'string',
                    'max:10',
                ],

                'email' => [
                    'required',
                    'string',
                    'email',
                    'max:255',

                    Rule::unique(
                        'users',
                        'email'
                    ),

                    Rule::unique(
                        'students',
                        'email'
                    ),
                ],

                'password' => [
                    'required',
                    'string',
                    'min:8',
                    'confirmed',

                    /*
                     * At least one uppercase letter.
                     */

                    'regex:/[A-Z]/',

                    /*
                     * At least one special character.
                     */

                    'regex:/[^A-Za-z0-9]/',
                ],

                /*
                |--------------------------------------------------------------------------
                | REFERENCE PHOTO
                |--------------------------------------------------------------------------
                */

                'profile_photo' => [
                    'required',
                    'file',
                    'image',
                    'mimes:jpeg,jpg,png',
                    'max:5048',
                ],

                /*
                |--------------------------------------------------------------------------
                | FORM 5
                |--------------------------------------------------------------------------
                |
                | Do not depend entirely on MIME detection.
                |
                | Some valid PDFs uploaded from macOS or browsers may be
                | detected as application/octet-stream.
                |
                | The actual PDF signature is checked below.
                |
                */

                'form_5' => [
                    'required',
                    'file',
                    'max:10240',
                ],
            ],
            [
                'student_number.regex' =>
                    'Student number must follow the format 24-010342.',

                'student_number.unique' =>
                    'This student number is already registered.',

                'email.unique' =>
                    'This email address is already registered.',

                'password.min' =>
                    'Password must contain at least 8 characters.',

                'password.confirmed' =>
                    'Password confirmation does not match.',

                'password.regex' =>
                    'Password must contain an uppercase letter and a special character.',

                'profile_photo.required' =>
                    'A reference photo is required.',

                'form_5.required' =>
                    'Your Form 5 document is required.',
            ]
        )->validate();

        /*
        |--------------------------------------------------------------------------
        | 2. NORMALIZE STUDENT NUMBER
        |--------------------------------------------------------------------------
        */

        $studentNumber = trim(
            $input['student_number']
        );

        /*
        |--------------------------------------------------------------------------
        | 3. EXTRACT INFORMATION FROM STUDENT NUMBER
        |--------------------------------------------------------------------------
        |
        | Example:
        |
        | 24-010342
        |
        | 24   = year code
        | 01   = college code
        | 0342 = unique sequence
        |
        */

        if (
            !preg_match(
                '/^(\d{2})-(\d{2})(\d{4})$/',
                $studentNumber,
                $matches
            )
        ) {
            throw ValidationException::withMessages([
                'student_number' =>
                    'Invalid student number. Expected format: 24-010342.',
            ]);
        }

        $yearCode = $matches[1];

        $collegeCode = $matches[2];

        $studentSequence = $matches[3];

        /*
        |--------------------------------------------------------------------------
        | 4. COLLEGE MAPPING
        |--------------------------------------------------------------------------
        |
        | Known college codes:
        |
        | 01 = CAFSD
        | 02 = CAS
        | 03 = CBEA
        | 04 = CTE
        | 05 = COE
        | 06 = UNKNOWN FOR NOW
        | 07 = CIT
        | 08 = CHS
        | 09 = GS
        | 10 = UNKNOWN FOR NOW
        | 11 = UNKNOWN FOR NOW
        | 12 = CVM
        | 13 = UNKNOWN FOR NOW
        | 14 = CCIS
        | 15 = UNKNOWN FOR NOW
        | 16 = UNKNOWN FOR NOW
        |
        | IMPORTANT:
        |
        | Unknown college names are intentionally stored as an empty
        | string for now. Their college CODE is still valid.
        |
        */

        $collegeMap = [
            '01' => 'CAFSD',
            '02' => 'CAS',
            '03' => 'CBEA',
            '04' => 'CTE',
            '05' => 'COE',
            '06' => '',
            '07' => 'CIT',
            '08' => 'CHS',
            '09' => 'GS',
            '10' => '',
            '11' => '',
            '12' => 'CVM',
            '13' => '',
            '14' => 'CCIS',
            '15' => '',
            '16' => '',
        ];

        /*
         * Reject codes that are completely outside the
         * currently recognized 01-16 range.
         *
         * Blank values inside the map are NOT rejected.
         */

        if (
            !array_key_exists(
                $collegeCode,
                $collegeMap
            )
        ) {
            throw ValidationException::withMessages([
                'student_number' =>
                    "College code {$collegeCode} from the student number is not recognized.",
            ]);
        }

        /*
         * Example:
         *
         * 24-010342
         *
         * college_code = 01
         * college      = CAFSD
         *
         *
         * Example with unknown college name:
         *
         * 24-060342
         *
         * college_code = 06
         * college      = ''
         */

        $college = $collegeMap[
            $collegeCode
        ];

        /*
        |--------------------------------------------------------------------------
        | 5. VALIDATE ACTUAL FORM 5 FILE
        |--------------------------------------------------------------------------
        |
        | Check the actual PDF signature instead of trusting
        | the browser/device MIME type.
        |
        */

        $form5File =
            $input['form_5'];

        $temporaryPdfPath =
            $form5File->getRealPath();

        if (
            !$temporaryPdfPath ||
            !is_file(
                $temporaryPdfPath
            )
        ) {
            throw ValidationException::withMessages([
                'form_5' =>
                    'Unable to read the uploaded Form 5.',
            ]);
        }

        $handle = fopen(
            $temporaryPdfPath,
            'rb'
        );

        if ($handle === false) {
            throw ValidationException::withMessages([
                'form_5' =>
                    'Unable to open the uploaded Form 5.',
            ]);
        }

        /*
         * Read enough bytes to tolerate a BOM or a small
         * amount of metadata before the PDF signature.
         */

        $header = fread(
            $handle,
            4096
        );

        fclose($handle);

        if (
            $header === false ||
            strpos(
                $header,
                '%PDF-'
            ) === false
        ) {
            throw ValidationException::withMessages([
                'form_5' =>
                    'The uploaded Form 5 is not a valid PDF document.',
            ]);
        }

        /*
        |--------------------------------------------------------------------------
        | 6. VERIFY REFERENCE FACE BEFORE DATABASE CREATION
        |--------------------------------------------------------------------------
        |
        | The Python face service checks whether a usable face
        | can be extracted from the uploaded reference photo.
        |
        */

        try {
            $photoEmbedding =
                $this->faceService
                    ->extractEmbeddingFromUploadedFile(
                        $input['profile_photo']
                    );
        } catch (RuntimeException $e) {
            throw ValidationException::withMessages([
                'profile_photo' =>
                    'Reference Photo Error: ' .
                    $e->getMessage(),
            ]);
        }

        /*
         * InsightFace embeddings should contain substantially
         * more than 100 values.
         */

        if (
            !is_array(
                $photoEmbedding
            ) ||
            count(
                $photoEmbedding
            ) < 100
        ) {
            throw ValidationException::withMessages([
                'profile_photo' =>
                    'Unable to generate a valid face embedding from the reference photo.',
            ]);
        }

        /*
        |--------------------------------------------------------------------------
        | 7. STORE FILES PRIVATELY
        |--------------------------------------------------------------------------
        */

        $photoPath = null;

        $pdfPath = null;

        try {
            /*
            |--------------------------------------------------------------------------
            | STORE REFERENCE PHOTO
            |--------------------------------------------------------------------------
            */

            $photoPath =
                $input['profile_photo']
                    ->store(
                        'profile_photos',
                        'private'
                    );

            /*
            |--------------------------------------------------------------------------
            | STORE FORM 5
            |--------------------------------------------------------------------------
            */

            $pdfPath =
                $input['form_5']
                    ->store(
                        'form_5_documents',
                        'private'
                    );

            /*
             * Get the absolute path so the OCR service can
             * process the stored PDF.
             */

            $pdfAbsolutePath =
                Storage::disk(
                    'private'
                )->path(
                    $pdfPath
                );

            /*
            |--------------------------------------------------------------------------
            | 8. OCR / FORM 5 VERIFICATION
            |--------------------------------------------------------------------------
            */

            $expectedFullName =
                implode(
                    ' ',
                    array_filter([
                        trim(
                            $input['firstname']
                        ),

                        trim(
                            $input['middlename']
                                ?? ''
                        ),

                        trim(
                            $input['surname']
                        ),

                        trim(
                            $input['ext']
                                ?? ''
                        ),
                    ])
                );

            $verificationResult =
                $this->form5Service
                    ->verifyAndExtract(
                        $pdfAbsolutePath,
                        $studentNumber,
                        $expectedFullName,
                    );

            /*
            |--------------------------------------------------------------------------
            | FORM 5 MUST MATCH REGISTRATION
            |--------------------------------------------------------------------------
            */

            if (
                !isset(
                    $verificationResult[
                        'is_verified'
                    ]
                ) ||
                !$verificationResult[
                    'is_verified'
                ]
            ) {
                $isLatestTerm =
                    $verificationResult[
                        'is_latest_term'
                    ] ?? true;

                throw ValidationException::withMessages([
                    'form_5' =>
                        !$isLatestTerm
                            ? 'The uploaded Form 5 is not valid for the current academic year or semester.'
                            : 'Form 5 verification failed. Make sure the student number and name match the uploaded Form 5.',
                ]);
            }

            /*
             * Information extracted from the Form 5.
             */

            $extractedData =
                $verificationResult[
                    'data'
                ] ?? [];

            /*
            |--------------------------------------------------------------------------
            | 9. CREATE STUDENT + USER ATOMICALLY
            |--------------------------------------------------------------------------
            */

            $user = DB::transaction(
                function () use (
                    $input,
                    $studentNumber,
                    $collegeCode,
                    $college,
                    $photoPath,
                    $pdfPath,
                    $photoEmbedding,
                    $extractedData
                ) {
                    /*
                    |--------------------------------------------------------------------------
                    | CREATE STUDENT
                    |--------------------------------------------------------------------------
                    */

                    $student =
                        Student::create([
                            'student_number' =>
                                $studentNumber,

                            'surname' =>
                                trim(
                                    $input['surname']
                                ),

                            'firstname' =>
                                trim(
                                    $input['firstname']
                                ),

                            'middlename' =>
                                !empty(
                                    $input['middlename']
                                )
                                    ? trim(
                                        $input[
                                            'middlename'
                                        ]
                                    )
                                    : null,

                            'ext' =>
                                !empty(
                                    $input['ext']
                                )
                                    ? trim(
                                        $input['ext']
                                    )
                                    : null,

                            'email' =>
                                strtolower(
                                    trim(
                                        $input['email']
                                    )
                                ),

                            /*
                            |--------------------------------------------------------------------------
                            | COLLEGE
                            |--------------------------------------------------------------------------
                            |
                            | Automatically derived from the
                            | student's student number.
                            |
                            */

                            'college_code' =>
                                $collegeCode,

                            'college' =>
                                $college,

                            /*
                            |--------------------------------------------------------------------------
                            | FORM 5 OCR DATA
                            |--------------------------------------------------------------------------
                            */

                            'degree' =>
                                $extractedData[
                                    'degree'
                                ] ?? null,

                            'year_section' =>
                                $extractedData[
                                    'year_section'
                                ] ?? null,

                            'semester' =>
                                $extractedData[
                                    'semester'
                                ] ?? null,

                            'academic_year' =>
                                $extractedData[
                                    'academic_year'
                                ] ?? null,

                            /*
                            |--------------------------------------------------------------------------
                            | DOCUMENTS + BIOMETRICS
                            |--------------------------------------------------------------------------
                            */

                            'face_photo_path' =>
                                $photoPath,

                            'form_5_path' =>
                                $pdfPath,

                            'face_embedding' =>
                                $photoEmbedding,

                            /*
                            |--------------------------------------------------------------------------
                            | VERIFICATION STATUS
                            |--------------------------------------------------------------------------
                            |
                            | Account exists, but the student must still
                            | complete LIVE liveness + face verification.
                            |
                            */

                            'verification_status' =>
                                'pending_face_verification',
                        ]);

                    /*
                    |--------------------------------------------------------------------------
                    | CREATE AUTHENTICATION USER
                    |--------------------------------------------------------------------------
                    */

                    return User::create([
                        'student_id' =>
                            $student
                                ->student_id,

                        'name' =>
                            trim(
                                $student
                                    ->firstname .
                                ' ' .
                                $student
                                    ->surname
                            ),

                        'email' =>
                            strtolower(
                                trim(
                                    $input['email']
                                )
                            ),

                        'password' =>
                            Hash::make(
                                $input[
                                    'password'
                                ]
                            ),

                        'role' =>
                            'student',
                    ]);
                }
            );

            /*
            |--------------------------------------------------------------------------
            | 10. VERIFY STUDENT RELATIONSHIP
            |--------------------------------------------------------------------------
            */

            $user->load(
                'student'
            );

            if (!$user->student) {
                throw new RuntimeException(
                    'Student account was created but its student relationship could not be loaded.'
                );
            }

            return $user;
        } catch (
            ValidationException $e
        ) {
            /*
            |--------------------------------------------------------------------------
            | DELETE STORED FILES WHEN VALIDATION FAILS
            |--------------------------------------------------------------------------
            */

            if ($photoPath) {
                Storage::disk(
                    'private'
                )->delete(
                    $photoPath
                );
            }

            if ($pdfPath) {
                Storage::disk(
                    'private'
                )->delete(
                    $pdfPath
                );
            }

            throw $e;
        } catch (Throwable $e) {
            /*
            |--------------------------------------------------------------------------
            | DELETE STORED FILES WHEN UNEXPECTED ERROR OCCURS
            |--------------------------------------------------------------------------
            */

            if ($photoPath) {
                Storage::disk(
                    'private'
                )->delete(
                    $photoPath
                );
            }

            if ($pdfPath) {
                Storage::disk(
                    'private'
                )->delete(
                    $pdfPath
                );
            }

            report($e);

            throw ValidationException::withMessages([
                'email' =>
                    'Registration failed. Please try again.',
            ]);
        }
    }
}