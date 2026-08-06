import type { Metadata } from "next";
import "./globals.css";
import { Providers } from "@/components/providers";
import { Layout } from "@/components/layout";
import StyledComponentsRegistry from "@/lib/styled-components-registry";
export const metadata: Metadata = {
  title: "Sonora — music for every mood",
  description: "A modern music streaming experience",
};
export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en">
      <body>
        <StyledComponentsRegistry>
          <Providers>
            <Layout>{children}</Layout>
          </Providers>
        </StyledComponentsRegistry>
      </body>
    </html>
  );
}
