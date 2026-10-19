<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

class EnsureUserIsOrganizer
{
    public function handle(Request $request, Closure $next): Response
    {
        $user = $request->user();

        if (!$user || !in_array($user->role, ['organizer', 'admin'])) {
            abort(403, 'Unauthorized access to Organizer portal.');
        }

        return $next($request);
    }
}