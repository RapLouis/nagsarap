<?php

namespace App\Http\Controllers\Student;

use App\Http\Controllers\Controller;
use App\Models\OrganizerApplication;
use App\Models\OrganizerKey;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Crypt;

class OrganizerApplyController extends Controller
{
    public function submit(Request $request)
    {
        $request->validate([
            'org_code' => 'required|string',
            'secret_key' => 'required|string',
            'organization_name' => 'required|string|max:255',
            'position' => 'required|string|max:255',
            'justification' => 'nullable|string',
        ]);

        // 1. Verify Org Code & Active Status
        $key = OrganizerKey::where('org_code', strtoupper($request->org_code))
            ->where('is_active', true)
            ->first();

        if (!$key) {
            return back()->withErrors(['org_code' => 'Invalid or inactive Organization Code.']);
        }

        // 2. Decrypt & Verify Secret Key
        try {
            $decryptedSecret = Crypt::decryptString($key->secret_key);
        } catch (\Exception $e) {
            return back()->withErrors(['secret_key' => 'Key verification error.']);
        }

        if ($request->secret_key !== $decryptedSecret) {
            return back()->withErrors(['secret_key' => 'Invalid Secret Key provided.']);
        }

        // 3. Check usage limits and expiration
        if ($key->uses_count >= $key->max_uses) {
            return back()->withErrors(['org_code' => 'This key has reached its maximum allowed uses.']);
        }

        if ($key->expires_at && now()->greaterThan($key->expires_at)) {
            return back()->withErrors(['org_code' => 'This key pair has expired.']);
        }

        // 4. Record Application
        OrganizerApplication::create([
            'user_id' => auth()->id(),
            'organizer_key_id' => $key->id,
            'organization_name' => $request->organization_name,
            'position' => $request->position,
            'justification' => $request->justification,
            'status' => 'pending',
        ]);

        return back()->with('success', 'Your application has been submitted for Admin approval.');
    }
}