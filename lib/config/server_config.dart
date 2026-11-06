/// Servidor de Canales que viene configurado de fábrica.
///
/// La clave "publishable" es PÚBLICA por diseño: solo permite lo que las
/// reglas de seguridad (RLS) del script supabase/instalar_canales.sql dejan
/// hacer. NUNCA poner aquí una clave secreta (sb_secret_… / service_role).
///
/// Otra institución puede usar su propio servidor desde la pestaña
/// Canales → "Cambiar servidor de canales".
class ServerConfig {
  ServerConfig._();
  static const supabaseUrl = 'https://wipdhhhcgodhkrqdvcnb.supabase.co';
  static const supabasePublishableKey = 'sb_publishable_Gew3IzpwPvqrZeD-FfT8nw_afwZQ65y';
}
