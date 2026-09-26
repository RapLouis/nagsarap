<?php

namespace App\Services;

use Exception;
use Illuminate\Support\Facades\Log;
use Smalot\PdfParser\Parser;
use Spatie\PdfToImage\Pdf;
use thiagocsf\Tesseract\Tesseract;

class Form5VerificationService
{
    /**
     * Process uploaded Form 5 PDF, verify student identity, and check for current term validity.
     */
    public function verifyAndExtract(string $pdfAbsolutePath, string $expectedStudentNumber, string $expectedFullName): array
    {
        $extractedText = '';

        // 1. Direct PDF Text Extraction
        try {
            $parser = new Parser();
            $pdfDocument = $parser->parseFile($pdfAbsolutePath);
            $extractedText = $pdfDocument->getText();
        } catch (Exception $e) {
            Log::warning('Smalot PDF parsing failed: ' . $e->getMessage());
        }

        // 2. OCR Fallback for scanned documents
        if (empty(trim($extractedText))) {
            $tempDirectory = storage_path('app/private/temp');

            if (!file_exists($tempDirectory)) {
                mkdir($tempDirectory, 0755, true);
            }

            $tempPngPath = $tempDirectory . '/' . uniqid('form5_full_') . '.png';

            try {
                $pdf = new Pdf($pdfAbsolutePath);
                $pdf->setPage(1)
                    ->setResolution(200)
                    ->saveImage($tempPngPath);

                $ocr = new Tesseract();
                $extractedText = $ocr->recognize($tempPngPath);
            } catch (Exception $e) {
                Log::error('Form 5 OCR Fallback Error: ' . $e->getMessage());
                return [
                    'is_verified'    => false,
                    'is_latest_term' => false,
                    'data'           => [],
                ];
            } finally {
                if (file_exists($tempPngPath)) {
                    unlink($tempPngPath);
                }
            }
        }

        // 3. Evaluate identity matches (Student Number AND Name)
        $hasIdentityMatch = $this->evaluateMatches($extractedText, $expectedStudentNumber, $expectedFullName);

        // 4. Parse document metadata
        $parsedData = $this->parseMetadata($extractedText);

        // 5. Evaluate dynamic calendar term match
        $isLatestTerm = $this->validateDynamicTerm($parsedData, $extractedText);

        return [
            'is_verified'    => $hasIdentityMatch && $isLatestTerm,
            'is_latest_term' => $isLatestTerm,
            'data'           => $parsedData,
        ];
    }

    /**
     * Dynamically validate extracted term against active calendar window.
     */
    private function validateDynamicTerm(array $parsedData, string $rawText): bool
    {
        [$expectedAY, $expectedSemTokens] = $this->getCurrentAcademicTerm();

        $normalizedRawText = $this->normalizeString($rawText);
        $extractedAY = $parsedData['academic_year'] ? $this->normalizeString($parsedData['academic_year']) : $normalizedRawText;
        $extractedSem = $parsedData['semester'] ? $this->normalizeString($parsedData['semester']) : $normalizedRawText;

        $hasAYMatch = str_contains($extractedAY, $this->normalizeString($expectedAY));

        $hasSemMatch = false;
        foreach ($expectedSemTokens as $token) {
            if (str_contains($extractedSem, $token)) {
                $hasSemMatch = true;
                break;
            }
        }

        return $hasAYMatch && $hasSemMatch;
    }

    /**
     * Compute active Academic Year and Semester tokens based on current system date.
     */
    private function getCurrentAcademicTerm(): array
    {
        $month = (int) date('n');
        $year  = (int) date('Y');

        if ($month >= 8 && $month <= 12) {
            $academicYear = $year . '-' . ($year + 1);
            $semesterTokens = ['FIRST', '1ST', 'SEM 1', 'SEMESTER 1'];
        } elseif ($month >= 1 && $month <= 5) {
            $academicYear = ($year - 1) . '-' . $year;
            $semesterTokens = ['SECOND', '2ND', 'SEM 2', 'SEMESTER 2'];
        } else {
            $academicYear = ($year - 1) . '-' . $year;
            $semesterTokens = ['MIDYEAR', 'SUMMER'];
        }

        return [$academicYear, $semesterTokens];
    }

    /**
     * Validate extracted text against input identity parameters.
     * Requires ALL entered name parts (Firstname, Surname, and Middlename) to match strictly.
     */
    private function evaluateMatches(string $extractedText, string $expectedStudentNumber, string $expectedFullName): bool
    {
        $normalizedText = $this->normalizeString($extractedText);
        $normalizedStudentNum = $this->normalizeString($expectedStudentNumber);

        // 1. Must match Student Number
        $hasNumberMatch = str_contains($normalizedText, $normalizedStudentNum);

        // 2. Tokenize user name inputs into distinct uppercase words
        $nameParts = array_values(array_filter(explode(' ', $this->normalizeString($expectedFullName))));
        
        if (empty($nameParts)) {
            return false;
        }

        // Tokenize document text into word array for exact word matching
        $documentWords = array_values(array_filter(explode(' ', $normalizedText)));

        $matchedCount = 0;

        foreach ($nameParts as $part) {
            // Exact word match inside document text stream
            if (in_array($part, $documentWords, true)) {
                $matchedCount++;
            }
        }

        // STRICT CHECK: Every single entered name word MUST exist in the document
        $hasAllNamesMatch = ($matchedCount === count($nameParts));

        return $hasNumberMatch && $hasAllNamesMatch;
    }

    /**
     * Parse metadata fields using key label regex search.
     */
    private function parseMetadata(string $text): array
    {
        $data = [
            'degree'        => null,
            'year_section'  => null,
            'semester'      => null,
            'academic_year' => null,
        ];

        // 1. DEGREE EXTRACTION
        if (preg_match('/Degree\s*:\s*(.+)/i', $text, $matches)) {
            // Isolate the first line of the matched block
            $firstLine = trim(explode("\n", $matches[1])[0]);

            // Separate tabbed column headers (e.g. "BS in Computer Science\tYear / Section: 4 - A")
            $firstColumn = explode("\t", $firstLine)[0];

            // Strip "Year / Section:" if separated by space instead of tab
            if (str_contains($firstColumn, 'Year / Section:')) {
                [$degreePart] = explode('Year / Section:', $firstColumn, 2);
                $firstColumn = $degreePart;
            }

            // Collapse multiple spaces and save clean degree string
            $data['degree'] = trim(preg_replace('/\s+/', ' ', $firstColumn));
        }

        // 2. YEAR & SECTION EXTRACTION
        if (preg_match('/Year\s*\/\s*Section\s*:\s*(.+)/i', $text, $matches)) {
            $rawSection = trim(explode("\n", $matches[1])[0]);
            $data['year_section'] = trim(preg_replace('/\s+/', ' ', $rawSection));
        }

        // 3. SEMESTER EXTRACTION
        if (preg_match('/Semester\s*:\s*(.+)/i', $text, $matches)) {
            $rawSemester = trim(explode("\n", $matches[1])[0]);
            $data['semester'] = trim(preg_replace('/\s+/', ' ', $rawSemester));
        }

        // 4. ACADEMIC YEAR EXTRACTION
        if (preg_match('/Academic\s*Year\s*:\s*(.+)/i', $text, $matches)) {
            $rawAY = trim(explode("\n", $matches[1])[0]);
            $data['academic_year'] = trim(preg_replace('/\s+/', ' ', $rawAY));
        }

        return $data;
    }

    /**
     * Convert string to uppercase alphanumeric tokens.
     */
    private function normalizeString(string $input): string
    {
        return strtoupper((string) preg_replace('/[^A-Za-z0-9]/', ' ', $input));
    }
}