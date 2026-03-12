import { BrowserRouter, Routes, Route } from 'react-router-dom';
import Header from './components/Header';
import UserList from './components/UserList';
import UserDetail from './components/UserDetail';

function App() {
  return (
    <BrowserRouter>
      <div className="app">
        <Header />
        <main>
          <Routes>
            <Route path="/" element={<UserList />} />
            <Route path="/users/:id" element={<UserDetail />} />
          </Routes>
        </main>
      </div>
    </BrowserRouter>
  );
}

export default App;
