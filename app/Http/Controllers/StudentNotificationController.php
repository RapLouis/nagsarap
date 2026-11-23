<?php

namespace App\Http\Controllers;

use App\Models\StudentNotification;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Inertia\Inertia;

class StudentNotificationController extends Controller
{
    /**
     * Display the student notification center.
     */
    public function index(Request $request)
    {
        /** @var \App\Models\User $user */
        $user = Auth::user();
        $student = $user->student;

        if (!$student) {
            return redirect()->route('dashboard');
        }

        $notifications = StudentNotification::where('student_id', $student->student_id)
            ->orderBy('created_at', 'desc')
            ->get()
            ->map(function ($notif) {
                return [
                    'notification_id' => $notif->notification_id,
                    'type' => $notif->type,
                    'title' => $notif->title,
                    'message' => $notif->message,
                    'is_read' => (bool) $notif->is_read,
                    'read_at' => $notif->read_at ? $notif->read_at->toIso8601String() : null,
                    'created_at' => $notif->created_at->diffForHumans(),
                ];
            });

        $unreadCount = StudentNotification::where('student_id', $student->student_id)
            ->where('is_read', false)
            ->count();

        return Inertia::render('Notifications', [
            'notifications' => $notifications,
            'unreadCount' => $unreadCount,
        ]);
    }

    /**
     * Mark a single notification as read.
     */
    public function markAsRead(StudentNotification $notification)
    {
        /** @var \App\Models\User $user */
        $user = Auth::user();
        $student = $user->student;

        if (!$student || $notification->student_id !== $student->student_id) {
            abort(403);
        }

        $notification->update([
            'is_read' => true,
            'read_at' => now(),
        ]);

        return back();
    }

    /**
     * Mark all notifications as read for the authenticated student.
     */
    public function markAllAsRead()
    {
        /** @var \App\Models\User $user */
        $user = Auth::user();
        $student = $user->student;

        if (!$student) {
            abort(403);
        }

        StudentNotification::where('student_id', $student->student_id)
            ->where('is_read', false)
            ->update([
                'is_read' => true,
                'read_at' => now(),
            ]);

        return back();
    }
}