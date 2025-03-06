import { Inter } from "next/font/google";
import "./globals.css";
import { AuthProvider } from "@/context/auth-provider";
import { ThemeProvider } from "@/context/theme-context";
// Add your other imports here

const inter = Inter({ subsets: ["latin"] });

export const metadata = {
  title: "Unify Poll",
  description: "Feature request application",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <body className={inter.className}>
        <ThemeProvider>
          <AuthProvider>
            {/* Your existing layout content */}
            {children}
          </AuthProvider>
        </ThemeProvider>
      </body>
    </html>
  );
}
