import { useEffect, useState } from "react";

export function UserAvatar({
  name,
  url,
  className = "",
}: {
  name?: string | null;
  url?: string | null;
  className?: string;
}) {
  const [failed, setFailed] = useState(false);
  const initial = (name || "用").charAt(0).toUpperCase();

  useEffect(() => {
    setFailed(false);
  }, [url]);

  return (
    <div
      className={`brand-gradient flex items-center justify-center overflow-hidden text-white font-bold ${className}`}
    >
      {url && !failed ? (
        <img
          src={url}
          alt=""
          className="h-full w-full object-cover"
          onError={() => setFailed(true)}
        />
      ) : (
        initial
      )}
    </div>
  );
}
