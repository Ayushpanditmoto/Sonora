"use client";
import { use } from "react";
import { useSong, useSuggestions } from "@/hooks/use-music";
import { DetailHero } from "@/components/detail-hero";
import { SongList } from "@/components/song-list";
import { artistNames } from "@/lib/utils";
import { PageShimmer, ErrorFallback } from "@/components/loading-shimmer";
export default function SongPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = use(params);
  const song = useSong(id);
  const related = useSuggestions(id);
  if (song.isLoading) return <PageShimmer />;
  if (song.isError || !song.data?.[0])
    return (
      <ErrorFallback
        message="Track unavailable."
        onRetry={() => song.refetch()}
      />
    );
  const track = song.data[0];
  return (
    <>
      <DetailHero
        type="Song"
        title={track.name}
        image={track.image}
        subtitle={`${artistNames(track.artists)} · ${track.album?.name || "Single"}`}
        songs={[track]}
      />
      <section className="mt-10">
        <h2 className="mb-4 text-2xl font-black">More like this</h2>
        {related.isLoading ? (
          <div className="space-y-3">
            {Array.from({ length: 7 }).map((_, i) => (
              <div key={i} className="shimmer h-14 rounded" />
            ))}
          </div>
        ) : related.isError ? (
          <ErrorFallback
            message="Couldn’t load suggestions."
            onRetry={() => related.refetch()}
          />
        ) : (
          (() => {
            const suggestions = (related.data || [])
              .filter((s) => s.id !== id)
              .slice(0, 10);
            if (!suggestions.length) {
              return <p className="text-zinc-400">No similar tracks found.</p>;
            }
            return <SongList songs={suggestions} />;
          })()
        )}
      </section>
    </>
  );
}
