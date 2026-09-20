<?php

namespace App\Exceptions;

use RuntimeException;

/** The Python biometric service was unreachable or returned something unusable. */
class BiometricServiceException extends RuntimeException
{
}