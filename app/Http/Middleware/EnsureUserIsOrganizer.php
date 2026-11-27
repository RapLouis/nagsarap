<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Symfony\Component\HttpFoundation\Response;

class EnsureUserIsOrganizer
{
    public function handle(Request $request, Closure $next): Response
    {
        $user = $request->user();

        if (!$user || !in_array($user->role, ['organizer', 'admin'])) {
            abort(403, 'Unauthorized access to Organizer portal.');
        }

        if ($user->role === 'organizer' && $user->status === 'suspended') {
            Auth::guard('web')->logout();
            $request->session()->invalidate();
            $request->session()->regenerateToken();

            return redirect()->route('login')->withErrors([
                'email' => 'Your organizer access has been suspended. Please contact an administrator.',
            ]);
        }

        return $next($request);
    }
}