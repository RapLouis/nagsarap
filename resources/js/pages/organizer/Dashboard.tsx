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
  Users,
  ShieldCheck,
  Clock,
  MapPin
} from 'lucide-react';

interface StudentInfo {
  name: string;
  student_number: string;
  degree?: string;
  year_section?: string;
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
  target_headcount?: number;
  approval_status?: 'pending' | 'approved' | 'declined';
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

export default function OrganizerDashboard({
  ongoingEvent,
  liveAttendance = [],
  eventAnalytics = [],
}: DashboardProps) {
  const maxAttendance = Math.max(
    ...(eventAnalytics?.map((e) => e.total_attendance) || [1]),
    1
  );

  return (
    <>
      <Head title="Organizer Control Center | 4ttnd Attendance System" />

      <div className="space-y-4 p-3 sm:p-5 font-sans text-gray-900 antialiased bg-[#F5F6FA] min-h-screen">
        
        {/* EXECUTIVE HEADER & QUICK ACTIONS */}
        <header className="flex flex-col sm:flex-row sm:items-center justify-between gap-3 bg-white p-4 sm:p-5 rounded-2xl border border-gray-200/80 shadow-xs">
          <div className="space-y-0.5">
            <h1 className="text-xl sm:text-2xl font-black text-[#1B1F5C] tracking-tight flex items-center gap-2">
              <span>Organizer Control Center</span>
              <span className="inline-flex items-center gap-1 px-2.5 py-0.5 rounded-full text-[10px] font-bold bg-indigo-50 text-[#1B1F5C] border border-indigo-200">
                <ShieldCheck className="w-3 h-3 text-[#F5A623]" aria-hidden="true" /> Active Hub
              </span>
            </h1>
            <p className="text-xs text-gray-500 font-medium">
              Monitor real-time biometric check-ins, oversee event turnout, and manage kiosk operations.
            </p>
          </div>

          <div className="flex items-center gap-2 shrink-0">
            <Link
              href="/organizer/kiosk"
              className="inline-flex items-center justify-center gap-2 px-4 py-2.5 min-h-[44px] bg-emerald-600 hover:bg-emerald-700 active:scale-98 text-white text-xs font-bold rounded-xl shadow-md transition-all focus-visible:ring-2 focus-visible:ring-[#F5A623]"
            >
              <Camera className="w-4 h-4 text-emerald-100" aria-hidden="true" />
              <span>Launch Kiosk Mode</span>
            </Link>
            <Link
              href="/organizer/events"
              className="inline-flex items-center justify-center gap-2 px-4 py-2.5 min-h-[44px] bg-[#1B1F5C] hover:bg-[#131644] active:scale-98 text-white text-xs font-bold rounded-xl shadow-md transition-all focus-visible:ring-2 focus-visible:ring-[#F5A623]"
            >
              <Plus className="w-4 h-4 text-[#FFD600]" aria-hidden="true" />
              <span>Create Event</span>
            </Link>
          </div>
        </header>

        {/* SUMMARY STATISTICS RIBBON CARDS */}
        <section aria-label="Event Data Summary" className="grid grid-cols-1 sm:grid-cols-3 gap-3">
          
          {/* Ongoing Event Card */}
          <div className="bg-white p-4 rounded-2xl border border-gray-200/80 shadow-xs flex items-center gap-3.5">
            <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-emerald-50 text-emerald-700 border border-emerald-100 shrink-0">
              <Activity className="h-5 w-5 animate-pulse" aria-hidden="true" />
            </div>
            <div className="min-w-0 flex-1">
              <span className="text-[10px] font-extrabold uppercase tracking-wider text-gray-500 block">Ongoing Event</span>
              {ongoingEvent ? (
                <div>
                  <span className="text-sm font-black text-gray-900 truncate block">{ongoingEvent.title}</span>
                  {ongoingEvent.location && (
                    <span className="text-[11px] text-gray-500 font-medium flex items-center gap-1 truncate mt-0.5">
                      <MapPin className="w-3 h-3 text-[#1B1F5C] shrink-0" aria-hidden="true" /> {ongoingEvent.location}
                    </span>
                  )}
                  <span className="inline-flex items-center gap-1.5 text-[10px] font-bold text-emerald-700 bg-emerald-50 px-2 py-0.5 rounded-full border border-emerald-200 mt-1">
                    <span className="h-1.5 w-1.5 rounded-full bg-emerald-500 animate-ping" aria-hidden="true" />
                    Live Attendance Active
                  </span>
                </div>
              ) : (
                <span className="text-xs text-gray-400 font-semibold italic mt-0.5 block">No active event currently</span>
              )}
            </div>
          </div>

          {/* Managed Events Card */}
          <div className="bg-white p-4 rounded-2xl border border-gray-200/80 shadow-xs flex items-center gap-3.5">
            <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-indigo-50 text-[#1B1F5C] border border-indigo-100 shrink-0">
              <Calendar className="h-5 w-5" aria-hidden="true" />
            </div>
            <div>
              <span className="text-[10px] font-extrabold uppercase tracking-wider text-gray-500 block">Managed Events</span>
              <span className="text-xl font-black text-gray-900 tracking-tight">{eventAnalytics?.length || 0}</span>
              <span className="text-[11px] text-gray-500 font-medium block mt-0.5">Submitted & Approved</span>
            </div>
          </div>

          {/* Today's Check-ins Card */}
          <div className="bg-white p-4 rounded-2xl border border-gray-200/80 shadow-xs flex items-center gap-3.5">
            <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-amber-50 text-amber-700 border border-amber-100 shrink-0">
              <Users className="h-5 w-5" aria-hidden="true" />
            </div>
            <div>
              <span className="text-[10px] font-extrabold uppercase tracking-wider text-gray-500 block">Today's Check-ins</span>
              <span className="text-xl font-black text-gray-900 tracking-tight">{liveAttendance.length}</span>
              <span className="text-[11px] text-gray-500 font-medium block mt-0.5">Biometric scans logged</span>
            </div>
          </div>
        </section>

        {/* MAIN DATA GRID */}
        <main className="grid grid-cols-1 lg:grid-cols-3 gap-4">
          
          {/* LIVE STREAM CHECK-INS FEED */}
          <section aria-label="Live Stream Check-ins" className="lg:col-span-1 bg-white rounded-2xl border border-gray-200/80 shadow-xs overflow-hidden flex flex-col">
            <div className="p-4 border-b border-gray-100 flex items-center justify-between">
              <div>
                <h2 className="text-xs sm:text-sm font-extrabold text-[#1B1F5C] flex items-center gap-2">
                  <CheckCircle className="h-4 w-4 text-emerald-600" aria-hidden="true" />
                  Live Attendance Stream
                </h2>
                <p className="text-[11px] text-gray-500 font-medium mt-0.5">Real-time biometric scans today</p>
              </div>
              <span className="h-2 w-2 rounded-full bg-emerald-500 animate-ping" title="Stream Active" aria-hidden="true" />
            </div>

            <div className="p-4 flex-1">
              {liveAttendance.length > 0 ? (
                <div className="space-y-2 max-h-[380px] overflow-y-auto pr-1" aria-live="polite">
                  {liveAttendance.map((item) => (
                    <div
                      key={item.id}
                      className="flex items-center justify-between p-2.5 bg-gray-50/70 rounded-xl border border-gray-100 hover:bg-gray-100/50 transition-colors"
                    >
                      <div className="min-w-0 pr-2">
                        <p className="text-xs font-extrabold text-gray-900 truncate">
                          {item.student?.name || 'Student'}
                        </p>
                        <p className="text-[11px] text-gray-500 font-mono font-medium mt-0.5">
                          {item.student?.student_number} {item.student?.degree ? `• ${item.student.degree}` : ''}
                        </p>
                      </div>
                      <div className="text-right shrink-0">
                        <span className="px-2 py-0.5 rounded-full text-[10px] font-extrabold bg-emerald-50 text-emerald-700 border border-emerald-200 block">
                          Verified
                        </span>
                        {item.created_at && (
                          <span className="text-[10px] text-gray-500 font-mono mt-0.5 block">
                            {new Date(item.created_at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
                          </span>
                        )}
                      </div>
                    </div>
                  ))}
                </div>
              ) : (
                <div className="py-14 text-center space-y-2">
                  <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-gray-100 text-gray-400 mx-auto">
                    <Clock className="w-5 h-5" aria-hidden="true" />
                  </div>
                  <p className="text-xs font-extrabold text-gray-800">No attendance recorded yet today.</p>
                  <p className="text-[11px] text-gray-500 font-medium">Scans from kiosk or mobile links will appear here instantly.</p>
                </div>
              )}
            </div>
          </section>

          {/* EVENT ATTENDANCE ANALYTICS & TURNOUT */}
          <section aria-label="Event Turnout Analytics" className="lg:col-span-2 bg-white rounded-2xl border border-gray-200/80 shadow-xs overflow-hidden flex flex-col">
            <div className="p-4 border-b border-gray-100 flex items-center justify-between">
              <div>
                <h2 className="text-xs sm:text-sm font-extrabold text-[#1B1F5C]">Event Attendance Analytics</h2>
                <p className="text-[11px] text-gray-500 font-medium mt-0.5">Turnout breakdown and approval statuses across organized events</p>
              </div>
              <Link 
                href="/organizer/events" 
                className="text-xs font-bold text-[#1B1F5C] hover:underline flex items-center gap-1 focus-visible:ring-2 focus-visible:ring-[#F5A623] rounded-md px-1.5 py-1 min-h-[38px]"
              >
                <span>Manage Events</span>
                <ArrowUpRight className="h-3.5 w-3.5 text-[#F5A623]" aria-hidden="true" />
              </Link>
            </div>

            <div className="p-4 flex-1">
              {eventAnalytics.length > 0 ? (
                <div className="space-y-3.5 max-h-[380px] overflow-y-auto pr-1">
                  {eventAnalytics.map((event) => {
                    const percentage = Math.round(
                      (event.total_attendance / maxAttendance) * 100
                    );
                    return (
                      <article key={event.id} className="space-y-1.5 p-3 bg-gray-50/60 rounded-xl border border-gray-100 hover:bg-gray-100/40 transition-colors">
                        <div className="flex items-center justify-between">
                          <div className="min-w-0 pr-2">
                            <span className="text-xs font-extrabold text-gray-900 truncate block">
                              {event.title}
                            </span>
                            <span className={`inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[9px] font-extrabold uppercase tracking-wider mt-1 border ${
                              event.approval_status === 'approved' 
                                ? 'bg-emerald-50 text-emerald-700 border-emerald-200' 
                                : event.approval_status === 'pending'
                                ? 'bg-amber-50 text-amber-700 border-amber-200'
                                : 'bg-rose-50 text-rose-700 border-rose-200'
                            }`}>
                              {event.approval_status || 'Approved'}
                            </span>
                          </div>
                          <span className="text-xs font-mono font-black text-[#1B1F5C] shrink-0">
                            {event.total_attendance} Attendances
                          </span>
                        </div>
                        <div className="w-full bg-gray-200 h-2 rounded-full overflow-hidden">
                          <div
                            className="h-full bg-[#1B1F5C] transition-all duration-500 rounded-full"
                            style={{ width: `${Math.min(percentage, 100)}%` }}
                          />
                        </div>
                      </article>
                    );
                  })}
                </div>
              ) : (
                <div className="py-14 text-center space-y-2">
                  <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-gray-100 text-gray-400 mx-auto">
                    <Calendar className="w-5 h-5" aria-hidden="true" />
                  </div>
                  <p className="text-xs font-extrabold text-gray-800">No event metrics available yet.</p>
                  <p className="text-[11px] text-gray-500 font-medium">Create and submit your first event to start tracking turnout.</p>
                </div>
              )}
            </div>
          </section>

        </main>
      </div>
    </>
  );
}

OrganizerDashboard.layout = (page: React.ReactNode) => (
  <OrganizerLayout title="Dashboard">{page}</OrganizerLayout>
);