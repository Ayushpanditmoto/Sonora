import type { NextConfig } from "next";
const nextConfig: NextConfig = {
  compiler: { styledComponents: true },
  images: {
    remotePatterns: [
      { protocol: "https", hostname: "c.saavncdn.com" },
      { protocol: "https", hostname: "*.saavncdn.com" },
      { protocol: "https", hostname: "www.jiosaavn.com" }
    ]
  }
};
export default nextConfig;
