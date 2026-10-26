import React from 'react';
import { Head, Link } from '@inertiajs/react';
import OrganizerLayout from '@/layouts/organizer-layout';
import { 
  Activity, 
  Calendar, 
  CheckCircle, 
  Camera, 
  Plus, 
  ArrowUpRight,
  Users
} from 'lucide-react';

interface StudentInfo {
  name: string;
  student_number: string;
}

interface LiveAttendanceItem {
  id: number;
  student?: StudentInfo;
  created_at?: string;
  slot_type?: string;
}

interface EventAnalytic {
  id: number;
  title: string;
  total_attendance: number;
  approval_status?: 'pending' | 'approved' | 'rejected';
}

interface OngoingEvent {
  event_id: number;
  title: string;
  location?: string | null;
  approval_status?: string;
}

interface DashboardProps {
  ongoingEvent?: OngoingEvent | null;
  liveAttendance?: LiveAttendanceItem[];
  eventAnalytics?: EventAnalytic[];
}

export default function Dashboard({
  ongoingEvent,
  liveAttendance = [],
  eventAnalytics = [],
}: DashboardProps) {
  const maxAttendance = Math.max(
    ...(eventAnalytics?.map((e) => e.total_attendance) || [1]),
    1
  );

  return (
    <OrganizerLayout title="Dashboard">
      <Head title="Organizer Control Panel" />

      <div className="space-y-6">
        
        {/* Page Title & Actions */}
        <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
          <div>
            <h1 className="text-xl font-bold text-slate-900">
              Organizer Control Panel
            </h1>
            <p className="text-xs text-gray-400 mt-0.5">
              Manage your department/club events, monitor live check-ins, and run kiosk scanners.
            </p>
          </div>

          <div className="flex items-center gap-2.5 shrink-0">
            <Link
              href="/organizer/kiosk"
              className="inline-flex items-center gap-2 px-4 py-2.5 bg-emerald-600 hover:bg-emerald-700 text-white text-xs font-semibold rounded-xl shadow-xs transition"
            >
              <Camera className="w-4 h-4" />
              Launch Kiosk Mode
            </Link>
            <Link
              href="/organizer/events"
              className="inline-flex items-center gap-2 px-4 py-2.5 bg-[#03045E] hover:bg-[#1D217D] text-white text-xs font-semibold rounded-xl shadow-xs transition"
            >
              <Plus className="w-4 h-4" />
              Create Event
            </Link>
          </div>
        </div>

        {/* STATS CARDS ROW (Matching Admin Design) */}
        <div className="grid grid-cols-1 sm:grid-cols-3 gap-5">
          {/* Ongoing Event Card */}
          <div className="bg-white p-6 rounded-2xl border border-gray-100 shadow-xs flex items-center gap-4">
            <div className="flex h-12 w-12 items-center justify-center rounded-2xl bg-emerald-50 text-emerald-600 shrink-0">
              <Activity className="h-6 w-6 animate-pulse" />
            </div>
            <div className="min-w-0 flex-1">
              <span className="text-[10px] font-bold uppercase tracking-wider text-gray-400 block">Ongoing Event</span>
              {ongoingEvent ? (
                <div>
                  <span className="text-base font-bold text-slate-900 truncate block">{ongoingEvent.title}</span>
                  <span className="inline-flex items-center gap-1 text-[10px] font-semibold text-emerald-600 bg-emerald-50 px-2 py-0.5 rounded-md mt-1">
                    <span className="h-1.5 w-1.5 rounded-full bg-emerald-500 animate-ping" />
                    Live Attendance
                  </span>
                </div>
              ) : (
                <span className="text-xs text-gray-400 italic">No active event currently</span>
              )}
            </div>
          </div>

          {/* Total Managed Events Card */}
          <div className="bg-white p-6 rounded-2xl border border-gray-100 shadow-xs flex items-center gap-4">
            <div className="flex h-12 w-12 items-center justify-center rounded-2xl bg-indigo-50 text-[#03045E] shrink-0">
              <Calendar className="h-6 w-6" />
            </div>
            <div>
              <span className="text-[10px] font-bold uppercase tracking-wider text-gray-400 block">Managed Events</span>
              <span className="text-2xl font-bold text-slate-900">{eventAnalytics?.length || 0}</span>
            </div>
          </div>

          {/* Today's Check-ins */}
          <div className="bg-white p-6 rounded-2xl border border-gray-100 shadow-xs flex items-center gap-4">
            <div className="flex h-12 w-12 items-center justify-center rounded-2xl bg-amber-50 text-amber-600 shrink-0">
              <Users className="h-6 w-6" />
            </div>
            <div>
              <span className="text-[10px] font-bold uppercase tracking-wider text-gray-400 block">Today's Check-ins</span>
              <span className="text-2xl font-bold text-slate-900">{liveAttendance.length}</span>
            </div>
          </div>
        </div>

        {/* MAIN DATA GRID */}
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
          
          {/* LIVE STREAM CHECK-INS */}
          <div className="lg:col-span-1 bg-white rounded-2xl border border-gray-100 shadow-xs overflow-hidden flex flex-col">
            <div className="p-5 border-b border-gray-100 flex items-center justify-between">
              <div>
                <h3 className="text-sm font-bold text-slate-900 flex items-center gap-2">
                  <CheckCircle className="h-4 w-4 text-emerald-600" />
                  Live Stream
                </h3>
                <p className="text-[11px] text-gray-400 mt-0.5">Recent biometric scans today</p>
              </div>
              <span className="h-2 w-2 rounded-full bg-emerald-500 animate-ping" />
            </div>

            <div className="p-5 flex-1">
              {liveAttendance.length > 0 ? (
                <div className="space-y-2.5 max-h-80 overflow-y-auto pr-1">
                  {liveAttendance.map((item: any) => (
                    <div
                      key={item.id}
                      className="flex items-center justify-between p-3 bg-gray-50/60 rounded-xl border border-gray-100"
                    >
                      <div className="min-w-0 pr-2">
                        <p className="text-xs font-bold text-slate-900 truncate">
                          {item.student?.name || 'Student'}
                        </p>
                        <p className="text-[11px] text-gray-400 font-mono">
                          {item.student?.student_number}
                        </p>
                      </div>
                      <span className="px-2.5 py-1 rounded-full text-[10px] font-semibold bg-emerald-50 text-emerald-700 border border-emerald-200/60">
                        Logged
                      </span>
                    </div>
                  ))}
                </div>
              ) : (
                <div className="py-12 text-center text-xs text-gray-400 italic">
                  No attendance recorded yet today.
                </div>
              )}
            </div>
          </div>

          {/* EVENT ATTENDANCE ANALYTICS */}
          <div className="lg:col-span-2 bg-white rounded-2xl border border-gray-100 shadow-xs overflow-hidden flex flex-col">
            <div className="p-5 border-b border-gray-100 flex items-center justify-between">
              <div>
                <h3 className="text-sm font-bold text-slate-900">Event Attendance Analytics</h3>
                <p className="text-[11px] text-gray-400 mt-0.5">Attendance breakdown across organized events</p>
              </div>
              <Link href="/organizer/events" className="text-xs font-semibold text-[#03045E] hover:underline flex items-center gap-1">
                Manage Events <ArrowUpRight className="h-3.5 w-3.5" />
              </Link>
            </div>

            <div className="p-5 flex-1">
              {eventAnalytics.length > 0 ? (
                <div className="space-y-4">
                  {eventAnalytics.map((event: any) => {
                    const percentage = Math.round(
                      (event.total_attendance / maxAttendance) * 100
                    );
                    return (
                      <div key={event.id} className="space-y-1.5">
                        <div className="flex justify-between text-xs font-medium">
                          <span className="text-slate-900 font-semibold truncate max-w-[280px]">
                            {event.title}
                          </span>
                          <span className="text-gray-500 font-mono">
                            {event.total_attendance} Attendances
                          </span>
                        </div>
                        <div className="w-full bg-gray-100 h-2.5 rounded-full overflow-hidden">
                          <div
                            className="h-full bg-[#03045E] transition-all duration-500 rounded-full"
                            style={{ width: `${percentage}%` }}
                          />
                        </div>
                      </div>
                    );
                  })}
                </div>
              ) : (
                <div className="py-12 text-center text-xs text-gray-400 italic">
                  No event metrics available yet.
                </div>
              )}
            </div>
          </div>

        </div>
      </div>
    </OrganizerLayout>
  );
}