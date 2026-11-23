import React, { useState } from 'react';
import { Calendar as CalendarIcon, CheckCircle2, Clock, AlertCircle, CalendarDays, MapPin } from 'lucide-react';
import { type TimeSlot } from '@/lib/eventValidation';

type ScheduleSlot = {
    slot_index: number;
    start_time: string; // Updated from start
    end_time: string;   // Updated from end
    checked_in: boolean;
    checked_out: boolean;
};

type ScheduleDay = {
    date: string;
    slots: ScheduleSlot[];
    day_status: 'attended' | 'partial' | 'absent' | 'upcoming' | 'active';
};

type CalendarEvent = {
    event_id: number;
    title: string;
    location?: string | null;
    schedules: ScheduleDay[];
};

type StudentCalendarProps = {
    calendarEvents: CalendarEvent[];
    today: string;
    onSelectSlotForCheckIn?: (event: CalendarEvent, slot: ScheduleSlot, dateStr: string) => void;
};

export default function StudentCalendar({ calendarEvents, today, onSelectSlotForCheckIn }: StudentCalendarProps) {
    const [selectedDate, setSelectedDate] = useState<string>(today);
    const [currentMonth, setCurrentMonth] = useState(new Date());

    // Map events and schedules by date string ('YYYY-MM-DD') for fast lookup
    const dateMap: Record<string, { event: CalendarEvent; day: ScheduleDay }[]> = {};
    calendarEvents.forEach((event) => {
        event.schedules.forEach((day) => {
            if (!dateMap[day.date]) {
                dateMap[day.date] = [];
            }
            dateMap[day.date].push({ event, day });
        });
    });

    // Helper status styling badges
    const getStatusBadge = (status: ScheduleDay['day_status']) => {
        switch (status) {
            case 'attended':
                return <span className="flex items-center gap-1 text-xs font-semibold text-emerald-600 bg-emerald-50 dark:bg-emerald-950/40 px-2 py-0.5 rounded-full"><CheckCircle2 className="w-3.5 h-3.5" /> Attended</span>;
            case 'partial':
                return <span className="flex items-center gap-1 text-xs font-semibold text-amber-600 bg-amber-50 dark:bg-amber-950/40 px-2 py-0.5 rounded-full"><Clock className="w-3.5 h-3.5" /> Partial</span>;
            case 'absent':
                return <span className="flex items-center gap-1 text-xs font-semibold text-rose-600 bg-rose-50 dark:bg-rose-950/40 px-2 py-0.5 rounded-full"><AlertCircle className="w-3.5 h-3.5" /> Missed</span>;
            default:
                return <span className="flex items-center gap-1 text-xs font-semibold text-indigo-600 bg-indigo-50 dark:bg-indigo-950/40 px-2 py-0.5 rounded-full"><CalendarDays className="w-3.5 h-3.5" /> Upcoming</span>;
        }
    };

    // Calendar grid generator logic for current month view
    const year = currentMonth.getFullYear();
    const month = currentMonth.getMonth();
    const firstDayOfMonth = new Date(year, month, 1).getDay();
    const daysInMonth = new Date(year, month + 1, 0).getDate();

    const monthDays = [];
    for (let i = 0; i < firstDayOfMonth; i++) {
        monthDays.push(null); // padding for empty leading days
    }
    for (let day = 1; day <= daysInMonth; day++) {
        const dateStr = `${year}-${String(month + 1).padStart(2, '0')}-${String(day).padStart(2, '0')}`;
        monthDays.push({ day, dateStr });
    }

    const selectedDayEvents = dateMap[selectedDate] || [];

    return (
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-6 bg-white dark:bg-[#090d16] p-6 rounded-2xl border border-gray-100 dark:border-slate-800 shadow-sm">
            
            {/* Left 2 Cols: Calendar Grid */}
            <div className="lg:col-span-2">
                <div className="flex items-center justify-between mb-6">
                    <h2 className="text-lg font-bold text-gray-900 dark:text-white flex items-center gap-2">
                        <CalendarIcon className="w-5 h-5 text-[#F5A623]" />
                        {currentMonth.toLocaleString('default', { month: 'long', year: 'numeric' })}
                    </h2>
                    <div className="flex items-center gap-2">
                        <button
                            onClick={() => setCurrentMonth(new Date(year, month - 1, 1))}
                            className="px-3 py-1 text-xs font-semibold rounded-lg bg-gray-100 dark:bg-slate-800 hover:bg-gray-200 dark:hover:bg-slate-700"
                        >
                            Prev
                        </button>
                        <button
                            onClick={() => setCurrentMonth(new Date(year, month + 1, 1))}
                            className="px-3 py-1 text-xs font-semibold rounded-lg bg-gray-100 dark:bg-slate-800 hover:bg-gray-200 dark:hover:bg-slate-700"
                        >
                            Next
                        </button>
                    </div>
                </div>

                {/* Day headers */}
                <div className="grid grid-cols-7 gap-2 text-center text-xs font-bold text-gray-400 mb-2">
                    <span>Sun</span><span>Mon</span><span>Tue</span><span>Wed</span><span>Thu</span><span>Fri</span><span>Sat</span>
                </div>

                {/* Days Grid */}
                <div className="grid grid-cols-7 gap-2">
                    {monthDays.map((item, index) => {
                        if (!item) return <div key={`empty-${index}`} />;
                        
                        const hasEvents = !!dateMap[item.dateStr];
                        const isSelected = selectedDate === item.dateStr;
                        const isToday = item.dateStr === today;
                        const dayStatus = hasEvents ? dateMap[item.dateStr][0].day.day_status : null;

                        // Dot color based on status
                        const dotColor = 
                            dayStatus === 'attended' ? 'bg-emerald-500' :
                            dayStatus === 'partial' ? 'bg-amber-500' :
                            dayStatus === 'absent' ? 'bg-rose-500' : 'bg-indigo-500';

                        return (
                            <button
                                key={item.dateStr}
                                onClick={() => setSelectedDate(item.dateStr)}
                                className={`relative flex flex-col items-center justify-center h-14 rounded-xl border transition-all ${
                                    isSelected 
                                        ? 'border-[#1B1F5C] dark:border-amber-400 bg-amber-50/50 dark:bg-amber-950/20 font-bold' 
                                        : 'border-gray-100 dark:border-slate-800 hover:border-gray-300 dark:hover:border-slate-700'
                                } ${isToday ? 'ring-2 ring-[#F5A623]' : ''}`}
                            >
                                <span className={`text-sm ${isToday ? 'text-[#F5A623] font-extrabold' : 'text-gray-700 dark:text-gray-300'}`}>
                                    {item.day}
                                </span>
                                {hasEvents && (
                                    <span className={`absolute bottom-2 w-2 h-2 rounded-full ${dotColor}`} />
                                )}
                            </button>
                        );
                    })}
                </div>
            </div>

            {/* Right Col: Slot-Level Breakdown Inspector */}
            <div className="bg-gray-50 dark:bg-slate-900/50 p-5 rounded-xl border border-gray-100 dark:border-slate-800 flex flex-col">
                <h3 className="text-sm font-bold text-gray-900 dark:text-white mb-3 flex items-center justify-between">
                    <span>Schedule of Events</span>
                    <span className="text-xs font-normal text-gray-500">{selectedDate}</span>
                </h3>

                <div className="flex-1 overflow-y-auto space-y-4 max-h-[380px]">
                    {selectedDayEvents.length === 0 ? (
                        <div className="flex flex-col items-center justify-center h-full text-center py-10 text-gray-400 text-xs">
                            <CalendarDays className="w-8 h-8 mb-2 opacity-40" />
                            No events scheduled for this date.
                        </div>
                    ) : (
                        selectedDayEvents.map(({ event, day }) => (
                            <div key={event.event_id} className="bg-white dark:bg-slate-800 p-4 rounded-xl border border-gray-100 dark:border-slate-700 shadow-sm space-y-3">
                                <div className="flex items-start justify-between">
                                    <div>
                                        <h4 className="text-sm font-bold text-gray-900 dark:text-white">{event.title}</h4>
                                        {event.location && (
                                            <p className="text-xs text-gray-500 flex items-center gap-1 mt-0.5">
                                                <MapPin className="w-3 h-3" /> {event.location}
                                            </p>
                                        )}
                                    </div>
                                    {getStatusBadge(day.day_status)}
                                </div>

                                {/* Slot Breakdown */}
                                <div className="space-y-2 pt-2 border-t border-gray-100 dark:border-slate-700">
                                    <p className="text-[11px] font-semibold text-gray-400 uppercase tracking-wider">Time Slots</p>
                                        {day.slots.map((slot) => (
                                            <div key={slot.slot_index} className="flex items-center justify-between text-xs bg-gray-50 dark:bg-slate-900 px-3 py-2 rounded-lg">
                                                <div>
                                                    <span className="font-semibold text-gray-800 dark:text-gray-200">Slot {slot.slot_index + 1}</span>
                                                    {/* Fix property names to match start_time and end_time */}
                                                    <span className="text-gray-400 ml-2">{slot.start_time} - {slot.end_time}</span>
                                                </div>
                                                <div className="flex items-center gap-2">
                                                    <span className={`px-1.5 py-0.5 rounded text-[10px] font-bold ${slot.checked_in ? 'bg-emerald-100 text-emerald-700 dark:bg-emerald-950 dark:text-emerald-300' : 'bg-gray-200 text-gray-600 dark:bg-slate-700 dark:text-gray-400'}`}>
                                                        In
                                                    </span>
                                                    <span className={`px-1.5 py-0.5 rounded text-[10px] font-bold ${slot.checked_out ? 'bg-emerald-100 text-emerald-700 dark:bg-emerald-950 dark:text-emerald-300' : 'bg-gray-200 text-gray-600 dark:bg-slate-700 dark:text-gray-400'}`}>
                                                        Out
                                                    </span>
                                                    {selectedDate === today && onSelectSlotForCheckIn && (!slot.checked_in || !slot.checked_out) && (
                                                        <button
                                                            onClick={() => onSelectSlotForCheckIn(event, slot, selectedDate)}
                                                            className="ml-1 px-2 py-1 text-[10px] font-bold text-white bg-[#1B1F5C] dark:bg-amber-500 rounded hover:opacity-90"
                                                        >
                                                            Check
                                                        </button>
                                                    )}
                                                </div>
                                            </div>
                                        ))}
                                </div>
                            </div>
                        ))
                    )}
                </div>
            </div>

        </div>
    );
}