import React, { Component, ErrorInfo, ReactNode } from 'react';
import { Alert, AlertTitle, AlertDescription } from '@/components/ui/alert';
import { Button } from '@/components/ui/button';
import { AlertCircle, RotateCcw, Home, RefreshCw } from 'lucide-react';
import { logError } from '@/lib/diagnostics';
import { ehChunkQueSumiu } from '@/lib/app-atualizado';

interface Props {
  children: ReactNode;
  fallback?: ReactNode;
}

interface State {
  hasError: boolean;
  error: Error | null;
  errorInfo: ErrorInfo | null;
}

export class GlobalErrorBoundary extends Component<Props, State> {
  public state: State = {
    hasError: false,
    error: null,
    errorInfo: null,
  };

  public static getDerivedStateFromError(error: Error): State {
    return { hasError: true, error, errorInfo: null };
  }

  public componentDidCatch(error: Error, errorInfo: ErrorInfo) {
    console.error('Uncaught error:', error, errorInfo);
    this.setState({ errorInfo });
    // A tela prometia que "nossos sistemas registraram o problema" e nada era gravado:
    // `logError` estava importado e nunca chamado. Justamente a tela branca — o erro que
    // ninguém consegue descrever depois — não deixava rastro nenhum em app_error_logs.
    void logError({
      message: error?.message || 'Erro não tratado na árvore de componentes',
      error,
      action: 'error_boundary',
      details: { componentStack: errorInfo?.componentStack?.slice(0, 2000) },
    });
  }

  private handleReset = () => {
    this.setState({ hasError: false, error: null, errorInfo: null });
    window.location.reload();
  };

  private handleGoHome = () => {
    this.setState({ hasError: false, error: null, errorInfo: null });
    window.location.href = '/';
  };

  public render() {
    if (this.state.hasError) {
      if (this.props.fallback) {
        return this.props.fallback;
      }

      // Tela publicada com a aba aberta: o arquivo da tela nova não existe mais com
      // aquele nome. Não é defeito, é versão velha — e dizer "Ops! Algo deu errado"
      // manda o usuário procurar um problema que não existe. Recarregar resolve.
      if (ehChunkQueSumiu(this.state.error)) {
        return (
          <div className="flex min-h-screen flex-col items-center justify-center bg-background p-4 md:p-8">
            <div className="w-full max-w-md space-y-6 text-center">
              <div className="mx-auto flex h-16 w-16 items-center justify-center rounded-full bg-primary/10">
                <RefreshCw className="h-8 w-8 text-primary" />
              </div>
              <div className="space-y-2">
                <h1 className="text-2xl font-bold tracking-tight">O sistema foi atualizado</h1>
                <p className="text-muted-foreground">
                  Esta aba ainda está usando a versão anterior. Recarregue para continuar —
                  nada do que você salvou se perdeu.
                </p>
              </div>
              <Button onClick={this.handleReset} className="gap-2" size="lg">
                <RefreshCw className="h-4 w-4" />
                Recarregar agora
              </Button>
            </div>
          </div>
        );
      }

      return (
        <div className="flex min-h-screen flex-col items-center justify-center p-4 md:p-8 animate-fade-in bg-background">
          <div className="w-full max-w-2xl space-y-6">
            <div className="flex flex-col items-center text-center space-y-2">
              <div className="h-16 w-16 rounded-full bg-destructive/10 flex items-center justify-center mb-2">
                <AlertCircle className="h-10 w-10 text-destructive" />
              </div>
              <h1 className="text-3xl font-bold tracking-tight">Ops! Algo deu errado</h1>
              <p className="text-muted-foreground max-w-md">
                Ocorreu um erro inesperado na aplicação. Nossos sistemas registraram o problema para análise.
              </p>
            </div>

            <Alert variant="destructive" className="border-destructive/20 bg-destructive/5">
              <AlertCircle className="h-4 w-4" />
              <AlertTitle>Detalhes do Erro</AlertTitle>
              <AlertDescription className="mt-2 font-mono text-xs overflow-auto max-h-32">
                {this.state.error?.toString()}
              </AlertDescription>
            </Alert>

            <div className="flex flex-col sm:flex-row gap-3 justify-center pt-4">
              <Button 
                onClick={this.handleReset}
                className="gap-2"
                variant="default"
              >
                <RotateCcw className="h-4 w-4" />
                Tentar Novamente
              </Button>
              <Button 
                onClick={this.handleGoHome}
                variant="outline"
                className="gap-2"
              >
                <Home className="h-4 w-4" />
                Voltar para o Início
              </Button>
            </div>

            <div className="pt-8 text-center">
              <p className="text-xs text-muted-foreground">
                Se o erro persistir, por favor entre em contato com o suporte técnico.
              </p>
            </div>
          </div>
        </div>
      );
    }

    return this.props.children;
  }
}
