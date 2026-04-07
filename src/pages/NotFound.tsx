import { useLocation } from "react-router-dom";
import { useEffect } from "react";
import { useI18n } from '@/i18n';

const NotFound = () => {
  const location = useLocation();
  const { t } = useI18n();

  useEffect(() => {
    console.error("404 Error: User attempted to access non-existent route:", location.pathname);
  }, [location.pathname]);

  return (
    <div className="flex min-h-[60vh] items-center justify-center">
      <div className="text-center">
        <h1 className="mb-4 text-4xl font-bold">{t.notFound.title}</h1>
        <p className="mb-4 text-xl text-muted-foreground">{t.notFound.message}</p>
        <a href="/" className="text-accent underline hover:text-accent/90">
          {t.notFound.backHome}
        </a>
      </div>
    </div>
  );
};

export default NotFound;
