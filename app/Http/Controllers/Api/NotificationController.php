<?php
namespace App\Http\Controllers\Api;
use App\Http\Controllers\Controller;
use App\Models\StudentNotification;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
class NotificationController extends Controller
{
 public function index(Request $r): JsonResponse { $sid=$r->user()->student_id; $items=StudentNotification::where('student_id',$sid)->latest()->get(); return response()->json(['success'=>true,'message'=>'Notifications retrieved successfully.','data'=>$items,'unread_count'=>$items->where('is_read',false)->count()]); }
 public function markAsRead(Request $r,int $notificationId): JsonResponse { $n=StudentNotification::where('notification_id',$notificationId)->where('student_id',$r->user()->student_id)->firstOrFail(); $n->update(['is_read'=>true,'read_at'=>now()]); return response()->json(['success'=>true,'message'=>'Notification marked as read.','data'=>$n->fresh()]); }
 public function markAllAsRead(Request $r): JsonResponse { StudentNotification::where('student_id',$r->user()->student_id)->where('is_read',false)->update(['is_read'=>true,'read_at'=>now(),'updated_at'=>now()]); return response()->json(['success'=>true,'message'=>'All notifications marked as read.']); }
}
