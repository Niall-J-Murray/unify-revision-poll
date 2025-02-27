"use client";

import { createContext, useContext } from "react";
import { SessionProvider, useSession, signOut } from "next-auth/react";

export function AuthProvider({ children }: { children: React.ReactNode }) {
  return <SessionProvider>{children}</SessionProvider>;
}

type AuthContextType = {
  user: any;
  loading: boolean;
  signOut: () => Promise<void>;
};

const AuthContext = createContext<AuthContextType>({
  user: null,
  loading: true,
  signOut: async () => {},
});

export const useAuth = () => useContext(AuthContext);

export function AuthContextProvider({
  children,
}: {
  children: React.ReactNode;
}) {
  const { data: session, status } = useSession();
  const loading = status === "loading";

  const handleSignOut = async () => {
    await signOut({ callbackUrl: "/" });
  };

  return (
    <AuthContext.Provider
      value={{
        user: session?.user || null,
        loading,
        signOut: handleSignOut,
      }}
    >
      {children}
    </AuthContext.Provider>
  );
}
