<?php
namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Event;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class EventController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $events=Event::with('days')->where('is_active',true)->where('approval_status','approved')->orderBy('event_date')->orderBy('created_at')->get();
        return response()->json(['success'=>true,'count'=>$events->count(),'data'=>$events->map(fn(Event $e)=>$this->payload($e))->values()]);
    }

    public function show(Event $event): JsonResponse
    {
        $event->load('days');
        return response()->json(['success'=>true,'data'=>$this->payload($event)]);
    }

    private function payload(Event $e): array
    {
        $days=$e->days->sortBy('event_date')->values(); $first=$days->first();
        $slots=$days->flatMap(fn($d)=>$d->slots??[]);
        $start=$slots->pluck('time_in_start')->filter()->sort()->first();
        $end=$slots->pluck('time_out_end')->filter()->sort()->last() ?? $slots->pluck('time_in_end')->filter()->sort()->last() ?? $slots->pluck('time_in_start')->filter()->sort()->last();
        return [
            'event_id'=>$e->event_id,'title'=>$e->title,'description'=>$e->description,
            'event_date'=>$first?->event_date?->format('Y-m-d'),'event_end_date'=>$days->last()?->event_date?->format('Y-m-d'),
            'start_time'=>$start,'end_time'=>$end,'location'=>$e->location,'latitude'=>$e->latitude,'longitude'=>$e->longitude,
            'geofence_radius'=>$e->radius_meters,'geofence_enabled'=>$e->is_geofenced,'geofence_type'=>$e->geofence_type,
            'geofence_polygon'=>$e->geofence_polygon,'late_after_minutes'=>15,'is_active'=>$e->is_active,
            'approval_status'=>$e->approval_status,'days'=>$days->map(fn($d)=>['event_day_id'=>$d->event_day_id,'event_date'=>$d->event_date->format('Y-m-d'),'slots'=>$d->slots])->values(),
            'created_at'=>$e->created_at,'updated_at'=>$e->updated_at,
        ];
    }
}
