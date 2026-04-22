import { forwardRef, useEffect, useState } from 'react';
import { Input } from '@/components/ui/input';
import { maskMoney, parseMoney, formatMoneyFromNumber } from '@/lib/masks';

type Props = Omit<React.ComponentProps<typeof Input>, 'value' | 'onChange' | 'type'> & {
  value: number | null | undefined;
  onValueChange: (value: number) => void;
};

/**
 * Money input no padrão BR (vírgula decimal, ponto para milhar).
 * Comportamento "caixa registradora": só aceita dígitos, formata da direita.
 */
export const MoneyInput = forwardRef<HTMLInputElement, Props>(
  ({ value, onValueChange, inputMode, ...rest }, ref) => {
    const [display, setDisplay] = useState<string>(() => formatMoneyFromNumber(value ?? 0));

    // Sincroniza quando o valor externo mudar e for diferente do que o input mostra
    useEffect(() => {
      const externalNumber = Number(value) || 0;
      const currentNumber = parseMoney(display);
      if (Math.abs(externalNumber - currentNumber) > 0.0001) {
        setDisplay(formatMoneyFromNumber(externalNumber));
      }
      // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [value]);

    const handleChange = (e: React.ChangeEvent<HTMLInputElement>) => {
      const raw = e.target.value;
      const masked = maskMoney(raw);
      setDisplay(masked);
      onValueChange(parseMoney(masked));
    };

    return (
      <Input
        ref={ref}
        type="text"
        inputMode={inputMode ?? 'numeric'}
        value={display}
        onChange={handleChange}
        placeholder="0,00"
        {...rest}
      />
    );
  }
);

MoneyInput.displayName = 'MoneyInput';
