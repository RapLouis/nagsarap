<?php
namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Storage;
use Illuminate\Validation\ValidationException;

class AuthController extends Controller
{
    public function login(Request $request): JsonResponse
    {
        $v=$request->validate(['student_number'=>['required','string','regex:/^\d{2}-\d{6}$/'],'password'=>['required','string']]);
        $user=User::with('student')->whereHas('student',fn($q)=>$q->where('student_number',trim($v['student_number'])))->first();
        if (!$user||!Hash::check($v['password'],$user->password)) throw ValidationException::withMessages(['student_number'=>'The student number or password is incorrect.']);
        if ($user->role!=='student') return response()->json(['success'=>false,'message'=>'This account cannot use the student mobile application.'],403);
        $user->tokens()->where('name','Flutter Android')->delete();
        $token=$user->createToken($request->input('device_name','Flutter Android'),['student'])->plainTextToken;
        return response()->json(['success'=>true,'message'=>'Login successful.','token'=>$token,'token_type'=>'Bearer','user'=>$this->userPayload($user),'student'=>$this->studentPayload($user->student)]);
    }

    public function me(Request $request): JsonResponse
    {
        $user=$request->user()->load('student');
        return response()->json(['success'=>true,'data'=>['user'=>$this->userPayload($user),'student'=>$this->studentPayload($user->student)]]);
    }

    public function profilePhoto(Request $request)
    {
        $student=$request->user()?->student; if (!$student||!$student->face_photo_path) return response()->json(['success'=>false,'message'=>'Profile photo not found.'],404);
        $disk=Storage::disk('private'); if (!$disk->exists($student->face_photo_path)) return response()->json(['success'=>false,'message'=>'Profile photo not found.'],404);
        return $disk->response($student->face_photo_path);
    }

    public function logout(Request $request): JsonResponse
    {
        $request->user()?->currentAccessToken()?->delete();
        return response()->json(['success'=>true,'message'=>'Logged out successfully.']);
    }

    private function userPayload(User $user): array { return ['id'=>$user->id,'student_id'=>$user->student_id,'name'=>$user->name,'email'=>$user->email,'role'=>$user->role]; }
    private function studentPayload($student): ?array
    {
        if (!$student) return null;
        $payload=$student->toArray(); $payload['profile_photo_url']=$student->face_photo_path?route('api.me.photo'):null; return $payload;
    }
}
