<?php
namespace App\Http\Controllers\Api;

use App\Actions\Fortify\CreateNewUser;
use App\Http\Controllers\Controller;
use App\Models\Student;
use App\Services\BiometricService;
use App\Services\FaceChallengeService;
use App\Exceptions\BiometricServiceException;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Storage;
use Illuminate\Validation\ValidationException;

class RegistrationController extends Controller
{
    public function validatePhoto(Request $request,BiometricService $bio): JsonResponse
    {
        $request->validate(['profile_photo'=>['required','image','mimes:jpeg,jpg,png','max:10240']]);
        try { $embedding=$bio->profileEmbeddingFromFile($request->file('profile_photo')); if(count($embedding)<100) throw new \RuntimeException('A usable face could not be extracted from this photo.'); return response()->json(['success'=>true,'code'=>'REFERENCE_PHOTO_VALID','message'=>'Face detected. Photo is ready for registration.']); }
        catch (\Throwable $e) { return response()->json(['success'=>false,'code'=>'REFERENCE_PHOTO_INVALID','message'=>$e->getMessage()],422); }
    }

    public function register(Request $request,CreateNewUser $creator): JsonResponse
    {
        $request->validate(['student_number'=>['required','string','regex:/^\d{2}-\d{6}$/'],'surname'=>['required','string','max:100'],'firstname'=>['required','string','max:100'],'middlename'=>['nullable','string','max:100'],'ext'=>['nullable','string','max:10'],'email'=>['required','email','max:255'],'password'=>['required','confirmed','string','min:12','regex:/[0-9]/','regex:/[^A-Za-z0-9]/'],'profile_photo'=>['required','image','mimes:jpeg,jpg,png','max:10240'],'form_5'=>['required','file','max:10240','mimetypes:application/pdf,application/x-pdf,application/acrobat,applications/vnd.pdf,text/pdf,text/x-pdf,application/octet-stream']]);
        try {
            $user=$creator->create($request->all());
            $token=$user->createToken($request->input('device_name','Flutter Android'),['student'])->plainTextToken;
            return response()->json(['success'=>true,'code'=>'REGISTRATION_CREATED','message'=>'Registration created. Complete live face verification.','data'=>['token'=>$token,'token_type'=>'Bearer','user'=>$user->load('student'),'student'=>$user->student]],201);
        } catch (ValidationException $e) { throw $e; }
    }

    public function analyzeLivenessFrame(Request $request,BiometricService $bio): JsonResponse
    {
        $request->validate(['frame'=>['required','image','mimes:jpeg,jpg,png','max:5048']]);
        try { $data=$bio->analyzeLivenessFrame($request->file('frame')); return response()->json(['success'=>true,'code'=>'LIVENESS_FRAME_ANALYZED','message'=>'Frame analyzed.','data'=>$data]); }
        catch (BiometricServiceException $e) { return response()->json(['success'=>false,'code'=>'LIVENESS_FRAME_FAILED','message'=>$e->getMessage()],422); }
    }

    public function verifyFace(Request $request,BiometricService $bio,FaceChallengeService $challenges): JsonResponse
    {
        $request->validate(['challenge_nonce'=>['required','string','max:100'],'session_id'=>['required','string','min:16','max:100'],'center_frame'=>['required','image','mimes:jpeg,jpg,png','max:5048'],'turned_frame'=>['required','image','mimes:jpeg,jpg,png','max:5048'],'returned_frame'=>['required','image','mimes:jpeg,jpg,png','max:5048']]);
        $student=$request->user()?->student; if (!$student) return response()->json(['success'=>false,'code'=>'STUDENT_NOT_FOUND','message'=>'Student record not found.'],404);
        if ($student->verification_status==='verified') return response()->json(['success'=>true,'code'=>'ALREADY_VERIFIED','message'=>'Biometric registration is already complete.','data'=>['student'=>$student,'verification_status'=>'verified']]);
        $challenge=$challenges->consume($student->student_id,$request->input('challenge_nonce'),$request->input('session_id'),'registration');
        if (!($challenge['valid']??false)) {
            return response()->json(['success'=>false,'code'=>'LIVENESS_CHALLENGE_INVALID','message'=>'Your liveness challenge is invalid or expired. Please start again.'],422);
        }
        $direction=$challenge['direction'];
        try { $live=$bio->verifyLiveness($direction,$request->file('center_frame'),$request->file('turned_frame'),$request->file('returned_frame')); }
        catch (BiometricServiceException $e) { return response()->json(['success'=>false,'code'=>'LIVENESS_FAILED','message'=>$e->getMessage()],422); }
        if (!($live['passed']??false)) return response()->json(['success'=>false,'code'=>'LIVENESS_FAILED','message'=>$live['detail']??'Liveness verification failed.','data'=>['reason_code'=>$live['reason_code']??null]],422);
        $reference=$bio->profileEmbedding($student);
        if (!$reference) return response()->json(['success'=>false,'code'=>'REFERENCE_FACE_FAILED','message'=>'Reference face data could not be found.'],422);
        $similarity=BiometricService::cosineSimilarity($live['frontal_embedding'],$reference); $threshold=(float)config('face_verification.profile_match_threshold',.50);
        if ($similarity<$threshold) return response()->json(['success'=>false,'code'=>'FACE_MISMATCH','message'=>'Live face does not match the uploaded profile photo.','data'=>['similarity'=>round($similarity,4),'required_similarity'=>$threshold]],422);
        $duplicateThreshold=(float)config('face_verification.duplicate_threshold',.60);
        foreach(Student::whereNotNull('face_embedding')->where('student_id','!=',$student->student_id)->select('student_id','face_embedding')->cursor() as $other) if(is_array($other->face_embedding)&&BiometricService::cosineSimilarity($live['frontal_embedding'],$other->face_embedding)>=$duplicateThreshold) return response()->json(['success'=>false,'code'=>'DUPLICATE_FACE','message'=>'This face is already registered to another student.'],409);
        $student->update(['face_embedding'=>$live['frontal_embedding'],'verification_status'=>'verified']);
        return response()->json(['success'=>true,'code'=>'BIOMETRICS_VERIFIED','message'=>'Biometric verification completed successfully.','data'=>['student'=>$student->fresh(),'similarity'=>round($similarity,4),'required_similarity'=>$threshold,'verification_status'=>'verified','liveness'=>$live,'direction'=>$direction]]);
    }
}
