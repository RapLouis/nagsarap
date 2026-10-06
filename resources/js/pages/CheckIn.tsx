import React, { useState, useEffect } from 'react';
import { Head } from '@inertiajs/react';
import {
    Calendar,
    Clock,
    ShieldCheck,
    MapPin,
} from 'lucide-react';
import CheckInModal from '@/components/CheckInModal';
import { type ScheduleItem, type TimeSlot } from '@/lib/eventValidation';
import { findSlotRecord, formatTime, windowState, type SlotType } from '@/lib/slots';
import { SlotStatusBadge, SlotWindowRow, slotBadge } from '@/components/slot-rows';

type Event = {
    event_id: number;
    title: string;
    description?: string | null;
    event_date: string;
    start_time: string;
    end_time?: string | null;
    location?: string | null;
    is_active?: boolean;
    geofence_enabled?: boolean;
    latitude?: number | null;
    longitude?: number | null;
    radius_meters?: number | null;
    schedules?: ScheduleItem[] | null;
};

type AttendanceLog = {
    attendance_id: number;
    logged_at: string;
    attendance_time: string;
    status: string;
    confidence_score: number;
    event: Event;
};

type Student = {
    student_id: number;
    firstname: string;
    surname: string;
    student_number: string;
    face_photo_url: string | null;
    attendances: AttendanceLog[];
};

type CheckInProps = {
    student: Student;
    activeEvents: Event[];
};

export default function CheckIn({ student, activeEvents }: CheckInProps) {
    const [selectedSlotEvent, setSelectedSlotEvent] = useState<{
        event: Event;
        slot: TimeSlot;
        slotIndex: number;
        dateStr: string;
        type: 'in' | 'out';
    } | null>(null);

    const [checkedInSlotsCache, setCheckedInSlotsCache] = useState<Set<string>>(() => new Set());

    const hasCheckedInSlot = (eventId: number, slotIndex: number, dateStr: string, type: SlotType) =>
        Boolean(findSlotRecord(student.attendances, eventId, dateStr, slotIndex, type));

    useEffect(() => {
        setCheckedInSlotsCache(new Set());
    }, [student]);

    return (
        <>
            <Head title="Student Check-In Hub" />

            <div className="w-full min-h-screen bg-gray-50 dark:bg-[#030712] text-gray-900 dark:text-white p-6 space-y-6 transition-colors duration-200">
                
                {/* HUB HEADER */}
                <div className="flex w-full items-center justify-between rounded-xl bg-white dark:bg-[#090d16] p-6 shadow-sm border border-gray-100 dark:border-slate-800/60">
                    <div>
                        <h1 className="text-xl font-bold text-gray-900 dark:text-white">
                            Attendance Check-In Hub
                        </h1>
                        <p className="text-xs text-gray-500 dark:text-gray-400 mt-1">
                            Select an ongoing event slot below to verify your identity and record your attendance.
                        </p>
                    </div>
                    <div className="flex items-center gap-1.5 rounded-full bg-emerald-50 dark:bg-emerald-950/30 px-3 py-1.5 text-xs font-semibold text-emerald-700 dark:text-emerald-400 border border-emerald-200 dark:border-emerald-800/40">
                        <ShieldCheck className="h-4 w-4" />
                        <span>Biometrics ready</span>
                    </div>
                </div>

                {/* ACTIVE EVENTS & SLOTS LIST */}
                <div className="w-full rounded-xl bg-white dark:bg-[#090d16] shadow-sm border border-gray-100 dark:border-slate-800/60 overflow-hidden">
                    <div className="flex items-center justify-between px-6 py-4 border-b border-gray-100 dark:border-slate-800/60">
                        <h2 className="text-base font-bold text-gray-900 dark:text-white">Events open for check-in</h2>
                        <span className="text-xs text-gray-400 dark:text-gray-500">{activeEvents.length} available</span>
                    </div>

                    {activeEvents.length === 0 ? (
                        <div className="flex flex-col items-center justify-center py-16 text-center">
                            <Calendar className="h-12 w-12 mb-3 stroke-1 text-gray-400 dark:text-gray-600" aria-hidden="true" />
                            <p className="text-sm font-medium text-gray-600 dark:text-gray-300">No active events right now</p>
                            <p className="text-xs text-gray-400 dark:text-gray-500 mt-1">Check back when your scheduled event window opens.</p>
                        </div>
                    ) : (
                        <ul className="divide-y divide-gray-100 dark:divide-slate-800/60">
                            {activeEvents.map((evt) => (
                                <li key={evt.event_id} className="p-6 space-y-4">
                                    <div className="flex items-center gap-3">
                                        <div className="flex h-12 w-12 shrink-0 items-center justify-center rounded-xl bg-indigo-50 dark:bg-slate-800/80 text-[#1B1F5C] dark:text-amber-400">
                                            <Clock className="h-5 w-5" aria-hidden="true" />
                                        </div>
                                        <div className="min-w-0 flex-1 space-y-0.5">
                                            <p className="text-sm font-bold text-gray-900 dark:text-white truncate">{evt.title}</p>
                                            <p className="text-xs text-gray-400 dark:text-gray-500 truncate flex items-center gap-1">
                                                <MapPin className="h-3 w-3 text-[#C9973E]" />
                                                {evt.location ? evt.location : 'Location TBA'}
                                            </p>
                                        </div>
                                    </div>

                                    {evt.schedules && evt.schedules.length > 0 && (
                                        <div className="grid grid-cols-1 md:grid-cols-2 gap-3 pl-2">
                                            {evt.schedules.map((sched, sIdx) => (
                                                <div key={sIdx} className="bg-gray-50 dark:bg-slate-900/60 rounded-xl p-3 border border-gray-100 dark:border-slate-800 space-y-3">
                                                    <p className="text-xs font-semibold text-gray-700 dark:text-gray-200">{sched.date}</p>
                                                    {sched.slots?.map((slot, slotIdx) => {
                                                        const inState = windowState(slot, 'in', sched.date);
                                                        const outState = windowState(slot, 'out', sched.date);
                                                        const inDone = hasCheckedInSlot(evt.event_id, slotIdx, sched.date, 'in');
                                                        const outDone = hasCheckedInSlot(evt.event_id, slotIdx, sched.date, 'out');
                                                        const badge = slotBadge({
                                                            hasIn: Boolean(slot.time_in_start),
                                                            hasOut: Boolean(slot.time_out_start),
                                                            inState,
                                                            outState,
                                                            inDone,
                                                            outDone,
                                                        });
                                                    
                                                        return (
                                                            <div key={slotIdx} className="space-y-2 pt-2 border-t border-gray-200/60 dark:border-slate-800">
                                                                <div className="flex items-center justify-between">
                                                                    <p className="text-[10px] font-semibold uppercase tracking-wider text-gray-400">Slot {slotIdx + 1}</p>
                                                                    <SlotStatusBadge status={badge} />
                                                                </div>
                                                    
                                                                {slot.time_in_start && (
                                                                    <SlotWindowRow
                                                                        label="In"
                                                                        time={formatTime(slot.time_in_start)}
                                                                        state={inState}
                                                                        done={inDone}
                                                                        doneLabel="Checked in"
                                                                        actionLabel="Check-In"
                                                                        onAction={() => setSelectedSlotEvent({ event: evt, slot, slotIndex: slotIdx, dateStr: sched.date, type: 'in' })}
                                                                    />
                                                                )}
                                                    
                                                                {slot.time_out_start && (
                                                                    <SlotWindowRow
                                                                        label="Out"
                                                                        time={formatTime(slot.time_out_start)}
                                                                        state={outState}
                                                                        done={outDone}
                                                                        doneLabel="Checked out"
                                                                        actionLabel="Check-Out"
                                                                        blockedReason={slot.time_in_start && !inDone ? 'Check in first' : null}
                                                                        onAction={() => setSelectedSlotEvent({ event: evt, slot, slotIndex: slotIdx, dateStr: sched.date, type: 'out' })}
                                                                    />
                                                                )}
                                                            </div>
                                                        );
                                                    })}
                                                </div>
                                            ))}
                                        </div>
                                    )}
                                </li>
                            ))}
                        </ul>
                    )}
                </div>
            </div>

            {/* SHARED LIVENESS CHECK-IN MODAL */}
            {selectedSlotEvent && (
                <CheckInModal 
                    event={selectedSlotEvent.event} 
                    slot={selectedSlotEvent.slot}
                    slotIndex={selectedSlotEvent.slotIndex}
                    dateStr={selectedSlotEvent.dateStr}
                    type={selectedSlotEvent.type}
                    onClose={() => setSelectedSlotEvent(null)} 
                />
            )}
        </>
    );
}