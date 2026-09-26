<?php
namespace App\Http\Controllers\Api;
use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\URL;
class WebVerificationController extends Controller
{
 public function create(Request $r): JsonResponse { $u=$r->user(); if(!$u||!$u->student_id) return response()->json(['success'=>false,'message'=>'Student profile not found.'],403); return response()->json(['success'=>true,'code'=>'WEB_VERIFY_URL_CREATED','message'=>'Biometric verification URL created.','data'=>['verified'=>$u->student?->verification_status==='verified','url'=>URL::temporarySignedRoute('mobile.register.verify-face.bridge',now()->addMinutes(10),['user'=>$u->getKey()],absolute:false)]]); }
}
