import React from 'react';
import { Head } from '@inertiajs/react';
import OrganizerLayout from '@/layouts/organizer-layout';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Activity, Calendar, CheckCircle2 } from 'lucide-react';

export default function Dashboard({ ongoingEvent, liveAttendance = [], eventAnalytics = [] }: any) {
  const maxAttendance = Math.max(...(eventAnalytics?.map((e: any) => e.total_attendance) || [1]), 1);

  return (
    <OrganizerLayout title="Dashboard">
      <Head title="Organizer Dashboard" />
      <div className="space-y-6 max-w-7xl">
        <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
          <Card className="border-l-4 border-l-green-500 shadow-xs bg-white">
            <CardHeader className="flex flex-row items-center justify-between pb-2">
              <CardTitle className="text-sm font-medium text-slate-500">Ongoing Event</CardTitle>
              <Activity className="h-4 w-4 text-green-500 animate-pulse" />
            </CardHeader>
            <CardContent>
              {ongoingEvent ? (
                <div>
                  <div className="text-xl font-bold text-slate-900">{ongoingEvent.title}</div>
                  <Badge className="mt-3 bg-green-100 text-green-800">Live Attendance Active</Badge>
                </div>
              ) : (
                <div className="text-slate-500 text-sm py-2">No ongoing event active today.</div>
              )}
            </CardContent>
          </Card>

          <Card className="shadow-xs bg-white">
            <CardHeader className="flex flex-row items-center justify-between pb-2">
              <CardTitle className="text-sm font-medium text-slate-500">My Total Events</CardTitle>
              <Calendar className="h-4 w-4 text-blue-500" />
            </CardHeader>
            <CardContent>
              <div className="text-2xl font-bold text-slate-900">{eventAnalytics?.length || 0}</div>
              <p className="text-xs text-slate-500 mt-1">Events created under your organizer account</p>
            </CardContent>
          </Card>
        </div>

        <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
          <Card className="lg:col-span-1 shadow-xs bg-white">
            <CardHeader>
              <CardTitle className="text-md font-semibold flex items-center gap-2 text-slate-900">
                <CheckCircle2 className="h-4 w-4 text-green-600" /> Live Stream Check-ins
              </CardTitle>
            </CardHeader>
            <CardContent>
              {liveAttendance.length > 0 ? (
                <div className="space-y-3">
                  {liveAttendance.map((item: any) => (
                    <div key={item.id} className="flex items-center justify-between p-2.5 bg-slate-50 rounded-lg border">
                      <div>
                        <p className="text-sm font-medium text-slate-800">{item.student?.name}</p>
                        <p className="text-xs text-slate-500">{item.student?.student_number}</p>
                      </div>
                    </div>
                  ))}
                </div>
              ) : (
                <p className="text-xs text-slate-400 py-6 text-center">No attendance recorded yet today.</p>
              )}
            </CardContent>
          </Card>

          <Card className="lg:col-span-2 shadow-xs bg-white">
            <CardHeader>
              <CardTitle className="text-md font-semibold text-slate-900">Event Attendance Analytics</CardTitle>
            </CardHeader>
            <CardContent>
              {eventAnalytics.length > 0 ? (
                <div className="space-y-4 pt-2">
                  {eventAnalytics.map((event: any) => {
                    const percentage = Math.round((event.total_attendance / maxAttendance) * 100);
                    return (
                      <div key={event.id} className="space-y-1">
                        <div className="flex justify-between text-xs font-medium">
                          <span className="text-slate-700 font-semibold">{event.title}</span>
                          <span className="text-slate-500 font-mono">{event.total_attendance} Attendance</span>
                        </div>
                        <div className="w-full bg-slate-100 h-3 rounded-full overflow-hidden">
                          <div className="h-full bg-blue-600 transition-all duration-500" style={{ width: `${percentage}%` }} />
                        </div>
                      </div>
                    );
                  })}
                </div>
              ) : (
                <p className="text-xs text-slate-400 py-8 text-center">No event metrics available.</p>
              )}
            </CardContent>
          </Card>
        </div>
      </div>
    </OrganizerLayout>
  );
}