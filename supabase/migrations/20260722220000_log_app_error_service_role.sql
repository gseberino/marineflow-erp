-- As edge functions rodam com service_role; log_app_error() foi concedida só a
-- authenticated. Sem este grant, o log vindo das edges falharia — e como a
-- própria função engole exceções, a falha seria invisível. Concede a execução.
GRANT EXECUTE ON FUNCTION public.log_app_error(text, text, text, text, text, jsonb) TO service_role;
