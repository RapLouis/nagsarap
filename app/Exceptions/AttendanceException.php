<?php

namespace App\Exceptions;

use RuntimeException;

class AttendanceException extends RuntimeException
{
    public function __construct(
        public readonly string $errorCode,
        string $message,
        public readonly int $httpStatus = 422,
        public readonly array $data = [],
    ) { parent::__construct($message); }
}
