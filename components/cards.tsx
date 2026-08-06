import Image from "next/image";
import Link from "next/link";
import type { Album, Artist, Playlist } from "@/types/music";
import { artistNames, imageUrl } from "@/lib/utils";
export function Card({
  item,
  type,
}: {
  item: Album | Artist | Playlist;
  type: "album" | "artist" | "playlist";
}) {
  const subtitle =
    type === "album"
      ? artistNames((item as Album).artists)
      : type === "playlist"
        ? `${(item as Playlist).songCount || 0} songs`
        : (item as Artist).role || "Artist";
  return (
    <Link
      href={`/${type}/${item.id}`}
      className="group rounded-lg bg-white/5 p-3 transition hover:bg-white/10"
    >
      <Image
        src={imageUrl(item.image)}
        alt={item.name}
        width={220}
        height={220}
        className={`aspect-square w-full object-cover shadow-lg ${type === "artist" ? "rounded-full" : "rounded-md"}`}
      />
      <p className="mt-3 truncate font-bold">{item.name}</p>
      <p className="mt-1 truncate text-sm text-zinc-400">{subtitle}</p>
    </Link>
  );
}
export function Cards({
  items,
  type,
}: {
  items: (Album | Artist | Playlist)[];
  type: "album" | "artist" | "playlist";
}) {
  return (
    <div className="grid grid-cols-2 gap-4 sm:grid-cols-3 lg:grid-cols-5">
      {items.map((item) => (
        <Card key={item.id} item={item} type={type} />
      ))}
    </div>
  );
}
