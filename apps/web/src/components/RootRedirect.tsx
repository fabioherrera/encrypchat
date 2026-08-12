"use client";

import { useEffect } from "react";

export function RootRedirect() {
  useEffect(() => {
    window.location.replace("/en");
  }, []);
  return null;
}
