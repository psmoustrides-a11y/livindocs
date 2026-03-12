import { Link } from 'react-router-dom';

function Header() {
  return (
    <header className="header">
      <nav>
        <Link to="/" className="logo">
          User Dashboard
        </Link>
        <div className="nav-links">
          <Link to="/">Users</Link>
        </div>
      </nav>
    </header>
  );
}

export default Header;
