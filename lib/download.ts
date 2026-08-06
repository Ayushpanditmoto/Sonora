import type { Song } from "@/types/music";

const filename = (name: string) =>
  name.replace(/[\\/:*?"<>|]/g, "-").trim() || "sonora-track";

export async function downloadSong(song: Song) {
  const url = song.downloadUrl?.at(-1)?.url;
  if (!url) throw new Error("No download source is available for this track.");
  const response = await fetch(url);
  if (!response.ok) throw new Error("The track could not be downloaded.");
  const blob = await response.blob();
  const objectUrl = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = objectUrl;
  link.download = `${filename(song.name)}.mp3`;
  document.body.appendChild(link);
  link.click();
  link.remove();
  URL.revokeObjectURL(objectUrl);
}
