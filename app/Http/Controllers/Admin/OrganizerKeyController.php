<?php

namespace App\Http\Controllers\Admin;

use App\Http\Controllers\Controller;
use App\Models\OrganizerApplication;
use App\Models\OrganizerKey;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Crypt;
use Illuminate\Support\Str;
use Inertia\Inertia;

class OrganizerKeyController extends Controller
{
    /**
     * Display key pairs and pending applications for Admin review.
     */
    public function index()
    {
        $keys = OrganizerKey::with('creator:id,name')
            ->orderBy('created_at', 'desc')
            ->get()
            ->map(function ($key) {
                try {
                    // Decrypt stored secret key for Admin toggle view
                    $key->plain_secret = Crypt::decryptString($key->secret_key);
                } catch (\Exception $e) {
                    $key->plain_secret = '••••••••';
                }
                return $key;
            });

        $applications = OrganizerApplication::with([
            'user:id,name,email',
            'user.student:student_id,degree,year_section',
            'key:id,org_code,key_name'
        ])
        ->orderBy('created_at', 'desc')
        ->get();

        return Inertia::render('admin/OrganizerKeys', [
            'keys' => $keys,
            'applications' => $applications,
        ]);
    }

    /**
     * Store a new Key Pair with Symmetric Encryption.
     */
    public function storeKey(Request $request)
    {
        $validated = $request->validate([
            'key_name' => 'required|string|max:255',
            'org_code' => 'required|string|unique:organizer_keys,org_code',
            'department' => 'nullable|string',
            'max_uses' => 'integer|min:1',
            'expires_at' => 'nullable|date',
        ]);

        $plainSecret = 'KEY-' . strtoupper(Str::random(8));

        OrganizerKey::create([
            'key_name' => $validated['key_name'],
            'org_code' => strtoupper($validated['org_code']),
            'secret_key' => Crypt::encryptString($plainSecret), // Encrypt using Laravel Crypt
            'department' => $validated['department'] ?? null,
            'max_uses' => $validated['max_uses'] ?? 1,
            'expires_at' => $validated['expires_at'] ?? null,
            'created_by' => auth()->id(),
        ]);

        return back()->with('success', 'New organizer key pair created successfully!');
    }

    /**
     * Toggle active state.
     */
    public function toggleKey($id)
    {
        $key = OrganizerKey::findOrFail($id);
        $key->update(['is_active' => !$key->is_active]);

        return back()->with('success', "Key pair status updated.");
    }

    /**
     * Approve Student Application.
     */
    public function approveApplication($id)
    {
        $application = OrganizerApplication::with(['user', 'key'])->findOrFail($id);

        if ($application->status !== 'pending') {
            return back()->with('error', 'Application is already processed.');
        }

        $application->update([
            'status' => 'approved',
            'reviewed_by' => auth()->id(),
            'reviewed_at' => now(),
        ]);

        $application->user->update(['role' => 'organizer']);

        if ($application->key) {
            $application->key->increment('uses_count');
        }

        return back()->with('success', "{$application->user->name} approved as an Organizer.");
    }

    /**
     * Reject Student Application.
     */
    public function rejectApplication(Request $request, $id)
    {
        $request->validate([
            'rejection_reason' => 'required|string|max:1000',
        ]);

        $application = OrganizerApplication::findOrFail($id);

        $application->update([
            'status' => 'rejected',
            'rejection_reason' => $request->rejection_reason,
            'reviewed_by' => auth()->id(),
            'reviewed_at' => now(),
        ]);

        return back()->with('success', 'Application rejected.');
    }
}