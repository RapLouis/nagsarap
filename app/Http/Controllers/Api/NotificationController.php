<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\StudentNotification;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class NotificationController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $user = $request->user();

        if (!$user) {
            return response()->json([
                'success' => false,
                'message' => 'Unauthenticated.',
                'data' => [],
                'unread_count' => 0,
            ], 401);
        }

        if (!$user->student_id) {
            return response()->json([
                'success' => false,
                'message' => 'No student profile is linked to this account.',
                'data' => [],
                'unread_count' => 0,
            ], 403);
        }

        $notifications = StudentNotification::query()
            ->where('student_id', $user->student_id)
            ->latest('created_at')
            ->get();

        $unreadCount = $notifications
            ->where('is_read', false)
            ->count();

        return response()->json([
            'success' => true,
            'message' => 'Notifications retrieved successfully.',
            'data' => $notifications,
            'unread_count' => $unreadCount,
        ]);
    }

    public function markAsRead(
        Request $request,
        int $notificationId
    ): JsonResponse {
        $user = $request->user();

        if (!$user) {
            return response()->json([
                'success' => false,
                'message' => 'Unauthenticated.',
            ], 401);
        }

        if (!$user->student_id) {
            return response()->json([
                'success' => false,
                'message' => 'No student profile is linked to this account.',
            ], 403);
        }

        $notification = StudentNotification::query()
            ->where(
                'notification_id',
                $notificationId
            )
            ->where(
                'student_id',
                $user->student_id
            )
            ->first();

        if (!$notification) {
            return response()->json([
                'success' => false,
                'message' => 'Notification not found.',
            ], 404);
        }

        if (!$notification->is_read) {
            $notification->update([
                'is_read' => true,
                'read_at' => now(),
            ]);
        }

        return response()->json([
            'success' => true,
            'message' => 'Notification marked as read.',
            'data' => $notification->fresh(),
        ]);
    }

    public function markAllAsRead(
        Request $request
    ): JsonResponse {
        $user = $request->user();

        if (!$user) {
            return response()->json([
                'success' => false,
                'message' => 'Unauthenticated.',
            ], 401);
        }

        if (!$user->student_id) {
            return response()->json([
                'success' => false,
                'message' => 'No student profile is linked to this account.',
            ], 403);
        }

        StudentNotification::query()
            ->where(
                'student_id',
                $user->student_id
            )
            ->where(
                'is_read',
                false
            )
            ->update([
                'is_read' => true,
                'read_at' => now(),
                'updated_at' => now(),
            ]);

        return response()->json([
            'success' => true,
            'message' => 'All notifications marked as read.',
        ]);
    }
}