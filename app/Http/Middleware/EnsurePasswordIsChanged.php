<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Symfony\Component\HttpFoundation\Response;

class EnsurePasswordIsChanged
{
    public function handle(Request $request, Closure $next): Response
    {
        $user = Auth::user();

        if ($user && $user->must_change_password) {
            // Exclude the change-password GET & POST routes and logout to prevent infinite loops
            if (!$request->routeIs('password.first-change*') && !$request->routeIs('logout')) {
                return redirect()->route('password.first-change');
            }
        }

        return $next($request);
    }
}