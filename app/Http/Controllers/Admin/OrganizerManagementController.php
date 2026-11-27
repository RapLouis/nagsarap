<?php

namespace App\Http\Controllers\Admin;

use App\Http\Controllers\Controller;
use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use Inertia\Inertia;

class OrganizerManagementController extends Controller
{
    public function index()
    {
        $organizers = User::where('role', 'organizer')
            ->orderBy('created_at', 'desc')
            ->get()
            ->map(function ($user) {
                return [
                    'id' => $user->id,
                    'name' => $user->name,
                    'email' => $user->email,
                    'department' => $user->organization_name ?? 'General Admin',
                    'key_code' => $user->key_code ?? '4TTND-ORG-' . strtoupper(substr(md5($user->id), 0, 6)),
                    'status' => $user->status ?? 'pending',
                    'events_managed_count' => $user->events()->count() ?? 0,
                    'created_at' => $user->created_at->toIso8601String(),
                ];
            });

        return Inertia::render('admin/Organizers', [
            'organizers' => $organizers,
        ]);
    }

    public function store(Request $request)
    {
        $validated = $request->validate([
            'name' => 'required|string|max:255',
            'email' => 'required|string|email|max:255|unique:users,email',
            'department' => 'nullable|string|max:255',
            'key_code' => 'required|string|max:255|unique:users,key_code',
            'password' => 'required|string', // Receives the key code from the frontend form
        ]);

        $rawDepartment = $validated['department'] ?? null;
        $trimmedDepartment = is_string($rawDepartment) ? trim($rawDepartment) : null;
        $organizationName = ($trimmedDepartment === '') ? null : $trimmedDepartment;

        User::create([
            'name' => $validated['name'],
            'email' => $validated['email'],
            'password' => Hash::make($validated['password']), // Uses key_code as their temporary password
            'role' => 'organizer',
            'organization_name' => $organizationName,
            'organization_position' => 'Event Organizer',
            'key_code' => $validated['key_code'],
            'status' => 'pending',
            'must_change_password' => true,
            'email_verified_at' => now(),
        ]);

        return back()->with('success', 'Organizer access key provisioned! Status set to Pending Activation.');
    }

    public function toggleStatus(User $user)
    {
        if ($user->role !== 'organizer') {
            return back()->with('error', 'Action restricted to organizer accounts.');
        }

        $mustChangePassword = $user->must_change_password;

        if ($user->status === 'active') {
            $newStatus = 'suspended';
        } elseif ($user->status === 'suspended') {
            $newStatus = $mustChangePassword ? 'pending' : 'active';
        } else {
            // If currently 'pending', manual activation clears the mandatory change
            $newStatus = 'active';
            $mustChangePassword = false;
        }

        $user->update([
            'status' => $newStatus,
            'must_change_password' => $mustChangePassword,
        ]);

        return back()->with('success', "Organizer account status updated to {$newStatus}.");
    }

    public function destroy(User $user)
    {
        if ($user->role !== 'organizer') {
            return back()->with('error', 'Action restricted to organizer accounts.');
        }

        $user->delete();

        return back()->with('success', 'Organizer record removed successfully.');
    }
}