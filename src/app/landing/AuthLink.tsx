import { appAuthHref } from "./appWebUrl";

type Variant = "primary" | "secondary" | "inverse" | "inverse-ghost";
type Size = "compact" | "regular";

const styles: Record<Variant, string> = {
  primary:
    "bg-accent text-white hover:brightness-95 focus-visible:outline-accent",
  secondary:
    "bg-transparent text-ink hover:bg-mist focus-visible:outline-accent",
  inverse: "bg-cream text-ink hover:bg-white focus-visible:outline-cream",
  "inverse-ghost":
    "bg-transparent text-cream hover:bg-white/10 focus-visible:outline-cream",
};

const sizes: Record<Size, string> = {
  compact: "px-4 py-2 text-sm",
  regular: "px-5 py-3 text-base",
};

export default function AuthLink({
  path,
  children,
  variant,
  size = "compact",
}: {
  path: "login" | "signup";
  children: React.ReactNode;
  variant: Variant;
  size?: Size;
}) {
  const href = appAuthHref(path);
  const classes = `inline-flex items-center justify-center rounded-full font-medium transition focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 disabled:cursor-not-allowed disabled:opacity-50 ${sizes[size]} ${styles[variant]}`;

  if (!href) {
    return (
      <button type="button" className={classes} disabled aria-disabled="true">
        {children}
      </button>
    );
  }

  return (
    <a href={href} className={classes}>
      {children}
    </a>
  );
}
