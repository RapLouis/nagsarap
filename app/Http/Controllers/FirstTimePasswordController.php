<?php

namespace App\Http\Controllers;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Hash;
use Illuminate\Validation\Rules\Password;
use Inertia\Inertia;

class FirstTimePasswordController extends Controller
{
    public function show()
    {
        return Inertia::render('auth/FirstTimeChangePassword');
    }

    public function update(Request $request)
    {
        $request->validate([
            'password' => ['required', 'confirmed', Password::defaults()],
        ]);

        /** @var \App\Models\User $user */
        $user = Auth::user();

        $user->update([
            'password' => Hash::make($request->password),
            'must_change_password' => false,
        ]);

        if ($user->role === 'organizer') {
            return redirect()->route('organizer.dashboard')->with('success', 'Password updated successfully! Welcome to your dashboard.');
        }

        return redirect()->route('dashboard');
    }
}