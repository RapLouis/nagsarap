import React, { ReactNode } from 'react';
import { Link, usePage } from '@inertiajs/react';
import {
  LayoutDashboard,
  Calendar,
  Camera,
  LogOut,
  ArrowLeftRight,
  ShieldCheck,
} from 'lucide-react';

interface Props {
  children: ReactNode;
  title?: string;
}

export default function OrganizerLayout({ children, title }: Props) {
  const { auth } = usePage<any>().props;
  const currentPath = usePage().url;

  const navItems = [
    {
      name: 'Dashboard Overview',
      href: '/organizer/dashboard',
      icon: LayoutDashboard,
    },
    {
      name: 'Manage My Events',
      href: '/organizer/events',
      icon: Calendar,
    },
    {
      name: 'Attendance Kiosk Mode',
      href: '/organizer/kiosk',
      icon: Camera,
    },
  ];

  return (
    <div className="min-h-screen bg-slate-50/50 text-slate-900 flex flex-col lg:flex-row">
      {/* SIDEBAR NAVIGATION */}
      <aside className="w-full lg:w-64 bg-white border-b lg:border-b-0 lg:border-r border-gray-100 flex flex-col justify-between p-5 shrink-0 shadow-xs">
        <div className="space-y-6">
          {/* BRAND / WORKSPACE HEADER */}
          <div className="px-1 py-0.5">
            <div className="flex items-center gap-3">
              <div className="h-9 w-9 bg-[#03045E] text-[#C9973E] rounded-xl flex items-center justify-center font-black text-xs shadow-xs shrink-0">
                4T
              </div>
              <div className="min-w-0">
                <h1 className="font-bold text-sm text-slate-900 truncate">
                  Organizer Hub
                </h1>
                <p className="text-[10px] text-gray-400 font-semibold tracking-wide uppercase">
                  Event Control
                </p>
              </div>
            </div>
          </div>

          {/* ROLE SWITCHER BANNER */}
          <div className="p-3 bg-[#03045E]/5 border border-[#03045E]/10 rounded-2xl space-y-2">
            <div className="flex items-center justify-between text-[11px] font-bold text-[#03045E]">
              <span className="flex items-center gap-1.5">
                <ShieldCheck className="w-4 h-4 text-[#C9973E]" />
                Organizer Mode
              </span>
            </div>
            <Link
              href="/dashboard"
              className="w-full inline-flex items-center justify-center gap-1.5 px-3 py-2 bg-[#03045E] hover:bg-[#1D217D] text-white rounded-xl text-xs font-semibold shadow-xs transition active:scale-98"
            >
              <ArrowLeftRight className="w-3.5 h-3.5 text-[#C9973E]" />
              Switch to Student View
            </Link>
          </div>

          {/* NAVIGATION LINKS */}
          <nav className="space-y-1">
            {navItems.map((item) => {
              const Icon = item.icon;
              const isActive = currentPath.startsWith(item.href);

              return (
                <Link
                  key={item.href}
                  href={item.href}
                  className={`flex items-center gap-3 px-3.5 py-2.5 rounded-xl text-xs font-semibold transition ${
                    isActive
                      ? 'bg-[#03045E] text-white shadow-xs'
                      : 'text-gray-600 hover:bg-gray-50 hover:text-slate-900'
                  }`}
                >
                  <Icon className={`w-4 h-4 shrink-0 ${isActive ? 'text-[#C9973E]' : 'text-gray-400'}`} />
                  {item.name}
                </Link>
              );
            })}
          </nav>
        </div>

        {/* USER PROFILE FOOTER */}
        <div className="pt-4 border-t border-gray-100 flex items-center justify-between">
          <div className="flex items-center gap-2.5 min-w-0">
            <div className="w-8 h-8 rounded-xl bg-indigo-50 text-[#03045E] font-bold flex items-center justify-center text-xs shrink-0 border border-indigo-100">
              {auth?.user?.name ? auth.user.name[0].toUpperCase() : 'O'}
            </div>
            <div className="min-w-0">
              <p className="text-xs font-bold text-slate-900 truncate">
                {auth?.user?.name}
              </p>
              <p className="text-[10px] text-gray-400 truncate">
                {auth?.user?.email}
              </p>
            </div>
          </div>
          <Link
            href="/logout"
            method="post"
            as="button"
            className="p-2 text-gray-400 hover:text-rose-600 hover:bg-rose-50 rounded-xl transition"
            title="Log Out"
          >
            <LogOut className="w-4 h-4" />
          </Link>
        </div>
      </aside>

      {/* MAIN CONTENT AREA */}
      <main className="flex-1 p-6 lg:p-8 overflow-y-auto">
        {children}
      </main>
    </div>
  );
}