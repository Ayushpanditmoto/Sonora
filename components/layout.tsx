"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { House, Search, Heart, ListMusic, LibraryBig } from "lucide-react";
import { MusicPlayer } from "@/components/music-player";
import clsx from "clsx";

const links = [
  {
    href: "/",
    label: "Home",
    icon: House,
  },
  {
    href: "/search",
    label: "Search",
    icon: Search,
  },
  {
    href: "/favorites",
    label: "Library",
    icon: LibraryBig,
  },
  {
    href: "/queue",
    label: "Queue",
    icon: ListMusic,
  },
];

export function Layout({ children }: { children: React.ReactNode }) {
  const pathname = usePathname();

  return (
    <div className="min-h-screen bg-black text-white">
      {/* Desktop Sidebar */}
      <aside className="fixed inset-y-0 left-0 hidden w-72 border-r border-white/10 bg-zinc-950 md:flex md:flex-col">
        {/* 🔥 Clickable Sonora logo → navigates to home */}
        <Link
          href="/"
          className="flex items-center gap-3 p-8 transition-opacity hover:opacity-80"
        >
          <div className="flex h-11 w-11 items-center justify-center rounded-full bg-emerald-500">
            <ListMusic className="text-black" />
          </div>
          <h1 className="text-2xl font-black">Sonora</h1>
        </Link>

        <nav className="space-y-2 px-4">
          {links.map(({ href, label, icon: Icon }) => (
            <Link
              key={href}
              href={href}
              className={clsx(
                "flex items-center gap-4 rounded-xl px-4 py-3 transition-all duration-200",
                pathname === href
                  ? "bg-emerald-500 text-black"
                  : "text-zinc-400 hover:bg-white/5 hover:text-white",
              )}
            >
              <Icon size={22} />
              <span className="font-semibold">{label}</span>
            </Link>
          ))}
        </nav>
      </aside>

      {/* Main */}
      <main className="pb-40 md:ml-72 md:pb-28">
        <div className="mx-auto max-w-7xl px-5 py-6">{children}</div>
      </main>

      {/* Mini Player */}
      <div className="fixed bottom-16 left-0 right-0 z-50 md:bottom-0 md:left-72">
        <MusicPlayer />
      </div>

      {/* Mobile Bottom Navigation */}
      <nav className="fixed bottom-0 left-0 right-0 z-40 border-t border-white/10 bg-zinc-950/95 backdrop-blur-xl md:hidden">
        <div className="flex h-16 items-center justify-around">
          {links.map(({ href, label, icon: Icon }) => (
            <Link
              key={href}
              href={href}
              className={clsx(
                "flex flex-col items-center justify-center gap-1 text-xs transition-colors",
                pathname === href ? "text-emerald-500" : "text-zinc-500",
              )}
            >
              <Icon size={22} />
              <span>{label}</span>
            </Link>
          ))}
        </div>
      </nav>
    </div>
  );
}
