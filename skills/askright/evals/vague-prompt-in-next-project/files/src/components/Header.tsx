export default function Header() {
  return (
    <header className="flex p-4">
      <img src="/logo.svg" className="w-40" />
      <nav className="flex gap-8 ml-4">
        <a href="/">Home</a><a href="/pricing">Pricing</a><a href="/docs">Docs</a><a href="/contact">Contact us</a>
      </nav>
    </header>
  );
}
