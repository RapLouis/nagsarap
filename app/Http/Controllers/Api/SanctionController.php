<?php
namespace App\Http\Controllers\Api;
use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
class SanctionController extends Controller
{
 public function index(Request $r): JsonResponse { $rows=DB::table('sanctions')->where('student_id',$r->user()->student_id)->orderByRaw('COALESCE(issued_at, created_at) DESC')->get(); return response()->json(['success'=>true,'message'=>'Sanctions retrieved successfully.','data'=>$rows]); }
}
