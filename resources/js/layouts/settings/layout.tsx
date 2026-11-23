import { Link } from '@inertiajs/react';
import type { PropsWithChildren } from 'react';
import Heading from '@/components/heading';
import { Button } from '@/components/ui/button';
import { Separator } from '@/components/ui/separator';
import { useCurrentUrl } from '@/hooks/use-current-url';
import { cn, toUrl } from '@/lib/utils';
import { edit as editAppearance } from '@/routes/appearance';
import { edit } from '@/routes/profile';
import { edit as editSecurity } from '@/routes/security';
import type { NavItem } from '@/types';

const sidebarNavItems: NavItem[] = [
    {
        title: 'Profile',
        href: edit(),
        icon: null,
    },
    {
        title: 'Security',
        href: editSecurity(),
        icon: null,
    },
    {
        title: 'Appearance',
        href: editAppearance(),
        icon: null,
    },
];

export default function SettingsLayout({ children }: PropsWithChildren) {
    const { isCurrentOrParentUrl } = useCurrentUrl();

    return (
        <div className="min-h-screen bg-[#F5F6FA] p-4 sm:p-6 lg:p-8 font-sans text-gray-900 antialiased space-y-6">
            <div className="max-w-7xl mx-auto space-y-6">
                <Heading
                    title="Account Settings"
                    description="Manage your profile information, security preferences, and theme appearance"
                />

                <div className="flex flex-col lg:flex-row lg:space-x-10 items-start">
                    {/* SETTINGS SIDEBAR NAVIGATION */}
                    <aside className="w-full lg:w-56 shrink-0 bg-white p-3 rounded-2xl border border-gray-200/80 shadow-xs">
                        <nav
                            className="flex flex-row lg:flex-col space-x-1 lg:space-x-0 lg:space-y-1 overflow-x-auto lg:overflow-x-visible pb-1 lg:pb-0"
                            aria-label="Settings navigation menu"
                        >
                            {sidebarNavItems.map((item, index) => {
                                const active = isCurrentOrParentUrl(item.href);
                                return (
                                    <Button
                                        key={`${toUrl(item.href)}-${index}`}
                                        size="sm"
                                        variant="ghost"
                                        asChild
                                        className={cn(
                                            'w-full justify-start min-h-[44px] px-3.5 text-xs font-bold transition-all focus-visible:ring-2 focus-visible:ring-[#F5A623]',
                                            {
                                                'bg-[#1B1F5C] text-white hover:bg-[#131644] hover:text-white shadow-sm': active,
                                                'text-gray-600 hover:bg-gray-100 hover:text-[#1B1F5C]': !active,
                                            }
                                        )}
                                    >
                                        <Link href={item.href}>
                                            {item.icon && (
                                                <item.icon className="mr-2 h-4 w-4 shrink-0" aria-hidden="true" />
                                            )}
                                            {item.title}
                                        </Link>
                                    </Button>
                                );
                            })}
                        </nav>
                    </aside>

                    <Separator className="my-6 lg:hidden border-gray-200" />

                    {/* SETTINGS CONTENT CONTAINER */}
                    <main className="flex-1 w-full max-w-4xl bg-white p-6 sm:p-8 rounded-3xl border border-gray-200/80 shadow-xs">
                        <div className="space-y-6">
                            {children}
                        </div>
                    </main>
                </div>
            </div>
        </div>
    );
}