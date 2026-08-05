import { clsx, type ClassValue } from "clsx";
import { twMerge } from "tailwind-merge";
export const cn = (...inputs: ClassValue[]) => twMerge(clsx(inputs));
export const duration = (seconds = 0) => `${Math.floor(seconds / 60)}:${String(Math.floor(seconds % 60)).padStart(2, "0")}`;
export const imageUrl = (images?: { url: string; quality: string }[]) => images?.at(-1)?.url || "/placeholder.svg";
export const artistNames = (artists?: { primary?: { name: string }[] }) => artists?.primary?.map(a => a.name).join(", ") || "Unknown artist";
export const decodeHtml = (value: string) => value.replace(/&quot;/g, '"').replace(/&#39;|&apos;/g, "'").replace(/&amp;/g, "&");
