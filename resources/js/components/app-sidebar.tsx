import { Link } from '@inertiajs/react';
import {
    Camera,
    Calendar,
    History,
    User,
    LayoutGrid,
} from 'lucide-react';
import AppLogo from '@/components/app-logo';
import { NavMain } from '@/components/nav-main';
import { NavUser } from '@/components/nav-user';
import {
    Sidebar,
    SidebarContent,
    SidebarFooter,
    SidebarHeader,
    SidebarMenu,
    SidebarMenuButton,
    SidebarMenuItem,
} from '@/components/ui/sidebar';
import { dashboard } from '@/routes';
import type { NavItem } from '@/types';

const NAVY = '#070b3f';

const mainNavItems: NavItem[] = [
    {
        title: 'Dashboard',
        href: dashboard(),
        icon: LayoutGrid,
    },
    {
        title: 'Check-in',
        href: '/check-in',
        icon: Camera,
    },
    {
        title: 'My events',
        href: '/events',
        icon: Calendar,
    },
    {
        title: 'Attendance history',
        href: '/attendance/history',
        icon: History,
    },
];

export function AppSidebar() {
    return (
        <Sidebar
            collapsible="icon"
            variant="sidebar"
            style={{ backgroundColor: NAVY }}
            className="border-r-0 text-white"
        >
            <SidebarHeader className="p-4">
                <SidebarMenu>
                    <SidebarMenuItem>
                        <SidebarMenuButton size="lg" asChild className="hover:bg-white/10 text-white">
                            <Link href={dashboard()} prefetch className="flex items-center gap-3">
                                <AppLogo />
                            </Link>
                        </SidebarMenuButton>
                    </SidebarMenuItem>
                </SidebarMenu>
            </SidebarHeader>

            <SidebarContent className="px-2">
                <NavMain items={mainNavItems} />
            </SidebarContent>

            <SidebarFooter className="p-4 border-t border-white/10">
                <NavUser />
            </SidebarFooter>
        </Sidebar>
    );
}