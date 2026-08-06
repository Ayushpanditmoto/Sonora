export interface Image {
  quality: string;
  url: string;
}
export interface Artist {
  id: string;
  name: string;
  role?: string;
  image?: Image[];
  url?: string;
}
export interface Artists {
  primary?: Artist[];
  featured?: Artist[];
  all?: Artist[];
}
export interface Album {
  id: string;
  name: string;
  year?: string;
  image?: Image[];
  artists?: Artists;
  url?: string;
}
export interface Song {
  id: string;
  name: string;
  duration: number;
  playCount?: number;
  language?: string;
  hasLyrics?: boolean;
  album?: Album;
  artists?: Artists;
  image?: Image[];
  downloadUrl?: { quality: string; url: string }[];
}
export interface Playlist {
  id: string;
  name: string;
  songCount?: number;
  image?: Image[];
  url?: string;
  description?: string;
  songs?: Song[];
}
export interface SearchResults<T> {
  total?: number;
  start?: number;
  results: T[];
}
export interface Detail<T> {
  success: boolean;
  data: T;
}
