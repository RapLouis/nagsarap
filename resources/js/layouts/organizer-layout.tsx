import React, { ReactNode } from 'react';
import { Link, usePage } from '@inertiajs/react';
import {
  LayoutDashboard,
  Calendar,
  Camera,
  LogOut,
  ShieldCheck,
} from 'lucide-react';

interface Props {
  children: ReactNode;
  title?: string;
}

export default function OrganizerLayout({ children }: Props) {
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
    <div className="min-h-screen bg-[#F5F6FA] text-gray-900 font-sans antialiased flex flex-col lg:flex-row">
      {/* SIDEBAR NAVIGATION */}
      <aside className="w-full lg:w-64 bg-white border-b lg:border-b-0 lg:border-r border-gray-200/80 flex flex-col justify-between p-5 shrink-0 shadow-sm">
        <div className="space-y-6">
          {/* BRAND / WORKSPACE HEADER */}
          <div className="px-1 py-0.5">
            <div className="flex items-center gap-3">
              <div className="h-10 w-10 bg-[#1B1F5C] text-[#FFD600] rounded-xl flex items-center justify-center font-black text-xs shadow-md shrink-0 ring-2 ring-[#F5A623]/20">
                4T
              </div>
              <div className="min-w-0">
                <h1 className="font-extrabold text-sm text-[#1B1F5C] truncate">
                  Organizer Hub
                </h1>
                <p className="text-[10px] text-gray-500 font-bold tracking-wider uppercase">
                  Event Control
                </p>
              </div>
            </div>
          </div>

          {/* NAVIGATION LINKS */}
          <nav className="space-y-1.5" aria-label="Organizer Sidebar Navigation">
            {navItems.map((item) => {
              const Icon = item.icon;
              const isActive = currentPath.startsWith(item.href);

              return (
                <Link
                  key={item.href}
                  href={item.href}
                  className={`flex items-center gap-3 min-h-[44px] px-3.5 py-2.5 rounded-xl text-xs font-bold transition-all focus-visible:ring-2 focus-visible:ring-[#F5A623] ${
                    isActive
                      ? 'bg-[#1B1F5C] text-white shadow-md'
                      : 'text-gray-600 hover:bg-gray-100 hover:text-[#1B1F5C]'
                  }`}
                >
                  <Icon className={`w-4 h-4 shrink-0 ${isActive ? 'text-[#FFD600]' : 'text-gray-400'}`} aria-hidden="true" />
                  {item.name}
                </Link>
              );
            })}
          </nav>
        </div>

        {/* USER PROFILE FOOTER */}
        <div className="pt-4 border-t border-gray-100 flex items-center justify-between mt-6 lg:mt-0">
          <div className="flex items-center gap-2.5 min-w-0">
            <div className="w-9 h-9 rounded-xl bg-indigo-50 text-[#1B1F5C] font-extrabold flex items-center justify-center text-xs shrink-0 border border-indigo-100">
              {auth?.user?.name ? auth.user.name[0].toUpperCase() : 'O'}
            </div>
            <div className="min-w-0">
              <p className="text-xs font-bold text-gray-900 truncate">
                {auth?.user?.name || 'Organizer'}
              </p>
              <p className="text-[10px] text-gray-500 font-medium truncate">
                {auth?.user?.email}
              </p>
            </div>
          </div>
          <Link
            href="/logout"
            method="post"
            as="button"
            className="p-2 min-h-[36px] text-gray-400 hover:text-red-600 hover:bg-red-50 rounded-xl transition-colors focus-visible:ring-2 focus-visible:ring-[#F5A623]"
            title="Log Out"
            aria-label="Log out of account"
          >
            <LogOut className="w-4 h-4" />
          </Link>
        </div>
      </aside>

      {/* MAIN CONTENT AREA */}
      <main className="flex-1 p-4 sm:p-6 lg:p-8 overflow-y-auto">
        {children}
      </main>
    </div>
  );
}