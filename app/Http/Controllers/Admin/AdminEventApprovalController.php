<?php

namespace App\Http\Controllers\Admin;

use App\Http\Controllers\Controller;
use App\Models\Event;
use Illuminate\Http\Request;

class AdminEventApprovalController extends Controller
{
    public function approve(Event $event)
    {
        $event->update(['status' => 'approved']);
        return redirect()->back()->with('success', "Event '{$event->title}' approved.");
    }

    public function reject(Event $event)
    {
        $event->update(['status' => 'rejected']);
        return redirect()->back()->with('success', "Event '{$event->title}' rejected.");
    }
}