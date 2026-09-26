<?php

namespace Database\Seeders;

use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\DB;

class StudentSeeder extends Seeder
{
    public function run(): void
    {
        $students = [
            // =========================
            // BS COMPUTER SCIENCE
            // =========================
            $this->student('23-140001', 'Dela Cruz', 'Juan', 'Santos', 'juan.delacruz@example.com', 1, '1 - A'),
            $this->student('23-140002', 'Garcia', 'Maria', 'Lopez', 'maria.garcia@example.com', 1, '1 - B'),
            $this->student('23-140003', 'Santos', 'Michael', 'Reyes', 'michael.santos@example.com', 1, '1 - C'),
            $this->student('23-140004', 'Reyes', 'Angela', 'Cruz', 'angela.reyes@example.com', 1, '2 - A'),
            $this->student('23-140005', 'Mendoza', 'Carlos', 'Ramos', 'carlos.mendoza@example.com', 1, '2 - B', 'Jr.'),
            $this->student('23-140006', 'Fernandez', 'Sofia', 'Garcia', 'sofia.fernandez@example.com', 1, '2 - C'),
            $this->student('23-140007', 'Villanueva', 'Daniel', 'Torres', 'daniel.villanueva@example.com', 1, '3 - A'),
            $this->student('23-140008', 'Aquino', 'John', 'Martin', 'john.aquino@example.com', 1, '3 - B'),
            $this->student('23-140009', 'Navarro', 'Christine', 'Mae', 'christine.navarro@example.com', 1, '3 - C'),
            $this->student('23-140010', 'Ramos', 'Mark', 'Anthony', 'mark.ramos@example.com', 1, '4 - A'),
            $this->student('23-140011', 'Torres', 'Patricia', 'Anne', 'patricia.torres@example.com', 1, '4 - B'),
            $this->student('23-140012', 'Castillo', 'Kevin', 'James', 'kevin.castillo@example.com', 1, '4 - C'),

            // =========================
            // BS INFORMATION TECHNOLOGY
            // =========================
            $this->student('23-150001', 'Bautista', 'Alex', 'Miguel', 'alex.bautista@example.com', 2, '1 - A'),
            $this->student('23-150002', 'Domingo', 'Nicole', 'Marie', 'nicole.domingo@example.com', 2, '1 - B'),
            $this->student('23-150003', 'Salazar', 'Ryan', 'Paul', 'ryan.salazar@example.com', 2, '1 - C'),
            $this->student('23-150004', 'Manalo', 'Jasmine', 'Rose', 'jasmine.manalo@example.com', 2, '2 - A'),
            $this->student('23-150005', 'Rivera', 'Joshua', 'Daniel', 'joshua.rivera@example.com', 2, '2 - B'),
            $this->student('23-150006', 'Flores', 'Stephanie', 'Joy', 'stephanie.flores@example.com', 2, '2 - C'),
            $this->student('23-150007', 'Mercado', 'Adrian', 'Luis', 'adrian.mercado@example.com', 2, '3 - A'),
            $this->student('23-150008', 'Pascual', 'Ella', 'Mae', 'ella.pascual@example.com', 2, '3 - B'),
            $this->student('23-150009', 'Gonzales', 'Matthew', 'John', 'matthew.gonzales@example.com', 2, '3 - C'),
            $this->student('23-150010', 'Estrada', 'Beatrice', 'Anne', 'beatrice.estrada@example.com', 2, '4 - A'),
            $this->student('23-150011', 'Lim', 'Nathan', 'Kyle', 'nathan.lim@example.com', 2, '4 - B'),
            $this->student('23-150012', 'Valdez', 'Camille', 'Grace', 'camille.valdez@example.com', 2, '4 - C'),
        ];

        DB::table('students')->insert($students);
    }

    /**
     * Create a student record with standard developmental defaults.
     */
    private function student(
        string $studentNumber,
        string $surname,
        string $firstname,
        ?string $middlename,
        string $email,
        int $degreeId,
        string $yearSection,
        ?string $ext = null
    ): array {
        $degree = $degreeId === 1
            ? 'BS in Computer Science'
            : 'BS in Information Technology';

        // Safe 512-D dummy embedding JSON payload
        $dummyEmbedding = json_encode(array_fill(0, 512, 0.0));

        return [
            'student_number'      => $studentNumber,
            'surname'             => $surname,
            'firstname'           => $firstname,
            'middlename'          => $middlename,
            'ext'                 => $ext,
            'email'               => $email,

            // Academic details
            'degree_id'           => $degreeId,
            'curricula_id'        => null,
            'degree'              => $degree,
            'year_section'        => $yearSection,
            'semester'            => 'First',
            'academic_year'       => '2026-2027',

            // Default biometric/system states
            'entrance_status'     => 1,
            'rfid'                => null,
            'form_5_path'         => null,
            'face_photo_path'     => null,
            'face_embedding'      => $dummyEmbedding,
            'verification_status' => 'verified',

            'created_at'          => now()->toDateTimeString(),
            'updated_at'          => now()->toDateTimeString(),
        ];
    }
}