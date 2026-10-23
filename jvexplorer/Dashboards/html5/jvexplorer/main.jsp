<%@ page language="java" contentType="text/html; charset=UTF-8" pageEncoding="UTF-8" session="true" trimDirectiveWhitespaces="true"%>
<%@ page import="java.io.*"%>
<%@ page import="java.net.*"%>
<%@ page import="java.nio.*"%>
<%@ page import="java.nio.charset.*"%>
<%@ page import="java.sql.*"%>
<%@ page import="java.util.*"%>
<%@ page import="java.util.jar.*"%>
<%@ page import="java.util.regex.*"%>
<%@ page import="javax.naming.*"%>
<%@ page import="javax.servlet.*"%>
<%@ page import="javax.servlet.http.*"%>
<%@ page import="javax.sql.*"%>
<%!
/* =====================================================================
   JVExplorer - visualizador de fontes de JAR (somente leitura)
   Padrao 4 (JSP Unificado): a mesma URL serve a interface e a API JSON.
   Nada e gravado em banco. O estado vive na HttpSession e em arquivos
   temporarios apagados quando a sessao morre.
   ===================================================================== */

private static final String SESS = "jvexplorer.estado";
private static final long MAX_JAR = 96L * 1024 * 1024;
private static final long MAX_EXPLODIDO = 512L * 1024 * 1024;
private static final int MAX_ENTRADAS = 60000;
private static final int BUFFER = 16384;

private static final Set<String> EXT_TEXTO = new HashSet<String>(Arrays.asList(
    "java", "kt", "xml", "xsd", "dtd", "tld", "properties", "mf", "txt", "sql",
    "json", "md", "yml", "yaml", "html", "htm", "js", "css", "csv", "sh", "bat",
    "cfg", "ini", "policy", "gradle", "jsp"));

/* Raizes de fonte usadas por builds Sankhya/Gradle: quando o JAR embute os
   .java em src/java, exibimos o fonte original em vez do bytecode reconstruido. */
private static final String[] RAIZES_FONTE = {
    "src/java/", "src/kotlin/", "src/main/java/", "src/main/kotlin/", "src/" };

private static volatile ClassLoader cfrLoader;
private static volatile String cfrPath;

/* ---------------------------------------------------------------- modelo */

public static final class No {
    String path;
    String tipo;
    String origem;
    long tamanho;
    File classe;
    File arquivo;
}

public static final class Estado implements HttpSessionBindingListener {
    File dir;
    File jar;
    File classes;
    File saida;
    File parcial;
    String nomeJar = "";
    String rotulo = "";
    int codModulo;
    int codJar;
    long tamanhoJar;
    int qtdClasses;
    int qtdEntradas;
    int seq;
    String analise;
    final Map<String, No> indice = new LinkedHashMap<String, No>();
    final Map<String, String> cache = new HashMap<String, String>();

    public void valueBound(HttpSessionBindingEvent evento) {
    }

    public void valueUnbound(HttpSessionBindingEvent evento) {
        apagar(dir);
    }
}

/* ------------------------------------------------------------- utilitario */

private static void apagar(File alvo) {
    if (alvo == null || !alvo.exists()) return;
    File[] filhos = alvo.listFiles();
    if (filhos != null) {
        for (File filho : filhos) apagar(filho);
    }
    alvo.delete();
}

private static String ext(String path) {
    int ponto = path.lastIndexOf('.');
    if (ponto < 0) return "";
    return path.substring(ponto + 1).toLowerCase(Locale.ENGLISH);
}

private static String nomeSimples(String path) {
    return path.substring(path.lastIndexOf('/') + 1);
}

private static String escapeJson(String texto) {
    if (texto == null) return "";
    StringBuilder sb = new StringBuilder(texto.length() + 16);
    for (int i = 0; i < texto.length(); i++) {
        char c = texto.charAt(i);
        if (c == '\\') sb.append("\\\\");
        else if (c == '"') sb.append("\\\"");
        else if (c == '\n') sb.append("\\n");
        else if (c == '\r') sb.append("\\r");
        else if (c == '\t') sb.append("\\t");
        else if (c < 0x20 || c == 0x2028 || c == 0x2029) sb.append(String.format("\\u%04x", (int) c));
        else sb.append(c);
    }
    return sb.toString();
}

private static byte[] lerBytes(File arquivo) throws IOException {
    ByteArrayOutputStream bos = new ByteArrayOutputStream((int) Math.max(64L, arquivo.length()));
    InputStream in = new BufferedInputStream(new FileInputStream(arquivo));
    try {
        byte[] buf = new byte[BUFFER];
        int lidos;
        while ((lidos = in.read(buf)) != -1) bos.write(buf, 0, lidos);
    } finally {
        in.close();
    }
    return bos.toByteArray();
}

/* Fontes Sankhya sao gravados em ISO-8859-1; tenta UTF-8 estrito primeiro. */
private static String lerTexto(File arquivo) throws IOException {
    byte[] bytes = lerBytes(arquivo);
    try {
        CharsetDecoder decoder = Charset.forName("UTF-8").newDecoder();
        decoder.onMalformedInput(CodingErrorAction.REPORT);
        decoder.onUnmappableCharacter(CodingErrorAction.REPORT);
        return decoder.decode(ByteBuffer.wrap(bytes)).toString();
    } catch (CharacterCodingException naoEhUtf8) {
        return new String(bytes, "ISO-8859-1");
    }
}

/* --------------------------------------------------------------- sessao */

private static File dirSessao(HttpSession sessao) {
    String id = sessao.getId().replaceAll("[^A-Za-z0-9]", "");
    return new File(new File(System.getProperty("java.io.tmpdir"), "jvexplorer"), id);
}

/* Cada upload do ZIP no OM recompila o JSP num pacote novo
   (html5component._<cod>_<timestamp>). O Estado gravado pela versao anterior tem
   o mesmo nome simples e outra Class: castar direto lanca ClassCastException e
   derruba todas as acoes ate a sessao expirar. Descarta o resto antigo e recomeca. */
private static synchronized Estado estado(HttpSession sessao) {
    Object gravado = sessao.getAttribute(SESS);
    if (gravado instanceof Estado) return (Estado) gravado;
    if (gravado != null) sessao.removeAttribute(SESS); // dispara valueUnbound: apaga o temp antigo
    Estado novo = new Estado();
    novo.dir = dirSessao(sessao);
    apagar(novo.dir);
    novo.dir.mkdirs();
    novo.classes = new File(novo.dir, "classes");
    novo.saida = new File(novo.dir, "fontes");
    novo.parcial = new File(novo.dir, "upload.part");
    novo.jar = new File(novo.dir, "app.jar");
    sessao.setAttribute(SESS, novo);
    return novo;
}

private static void limpar(Estado estado) {
    apagar(estado.classes);
    apagar(estado.saida);
    apagar(estado.jar);
    apagar(estado.parcial);
    estado.indice.clear();
    estado.cache.clear();
    estado.analise = null;
    estado.nomeJar = "";
    estado.rotulo = "";
    estado.codModulo = 0;
    estado.codJar = 0;
    estado.tamanhoJar = 0;
    estado.qtdClasses = 0;
    estado.qtdEntradas = 0;
}

/* ---------------------------------------------------------------- banco */

/* O JSP nao importa classes Sankhya: um pacote fora de lugar impediria a
   compilacao e derrubaria a tela inteira, inclusive o upload manual. O acesso
   ao banco vai todo por reflection sobre o JAPE, com fallback de DataSource
   por JNDI. Quando nada resolve, so o modo de upload continua disponivel. */
private static final String[] DS_JNDI = {
    "java:/jdbc/sankhyaDS", "java:jboss/datasources/SankhyaDS",
    "java:/SankhyaDS", "java:/jdbc/SankhyaDS", "jdbc/sankhyaDS" };

private static final String SQL_MODULOS =
    "SELECT M.CODMODULO, M.DESCRMODULO, M.RESOURCEID,"
  + " (SELECT COUNT(1) FROM TSIJAR J WHERE J.CODMODULO = M.CODMODULO) QTDJAR"
  + " FROM TSIMOD M"
  + " WHERE UPPER(M.DESCRMODULO) LIKE ? ESCAPE '\\' OR UPPER(M.RESOURCEID) LIKE ? ESCAPE '\\'"
  + " ORDER BY M.DESCRMODULO";

private static final String SQL_JAR =
    "SELECT M.DESCRMODULO, J.DESCRICAO, J.ARQUIVO"
  + " FROM TSIJAR J INNER JOIN TSIMOD M ON M.CODMODULO = J.CODMODULO"
  + " WHERE J.CODMODULO = ? AND J.CODJAR = ?";

private static volatile String origemBanco = "";

public static final class Conexao {
    Connection conn;
    Object jdbc;
    Object handle;
    Class<?> jape;
    String origem = "";
    boolean oracle;
}

private static String descrever(Throwable falha) {
    if (falha == null) return "sem detalhe";
    String mensagem = falha.getMessage();
    return mensagem == null || mensagem.length() == 0 ? falha.getClass().getName() : mensagem;
}

/* Ler TSIJAR expoe o fonte de tudo que esta instalado: so o SUP consulta a base. */
private static Class<?> classeAuth() throws ClassNotFoundException {
    return Thread.currentThread().getContextClassLoader()
        .loadClass("br.com.sankhya.modelcore.auth.AuthenticationInfo");
}

/* getCurrent() lanca AuthenticationException quando o ThreadLocal esta vazio, e
   ele so e populado por AuthenticationServiceContext.setup nos filtros de
   servico - a thread que serve este JSP frequentemente nao passa por lah. */
private static Object autenticacaoDaThread() {
    try {
        return classeAuth().getMethod("getCurrentOrNull").invoke(null);
    } catch (Throwable semThreadLocal) {
        return null;
    }
}

private static Object autenticacaoDaSessao(HttpSession sessao, StringBuilder onde) {
    Class<?> auth;
    try {
        auth = classeAuth();
    } catch (Throwable semClasse) {
        return null;
    }
    Enumeration<String> nomes = sessao.getAttributeNames();
    while (nomes.hasMoreElements()) {
        String nome = nomes.nextElement();
        Object valor = sessao.getAttribute(nome);
        if (!auth.isInstance(valor)) continue;
        onde.setLength(0);
        onde.append("httpsession:").append(nome);
        return valor;
    }
    return null;
}

private static Object autenticacao(HttpSession sessao, StringBuilder onde) {
    Object atual = autenticacaoDaThread();
    if (atual != null) {
        onde.setLength(0);
        onde.append("threadlocal");
        return atual;
    }
    return autenticacaoDaSessao(sessao, onde);
}

private static boolean ehSup(HttpSession sessao) {
    StringBuilder onde = new StringBuilder();
    Object atual = autenticacao(sessao, onde);
    if (atual == null) return false;
    try {
        return Boolean.TRUE.equals(atual.getClass().getMethod("isSUP").invoke(atual));
    } catch (Throwable semIsSup) {
        return false;
    }
}

private static final String AVISO_SUP =
    "Verificar modulos da base e permitido somente para o usuario SUP.";

private static void exigirSup(HttpSession sessao) throws IOException {
    if (ehSup(sessao)) return;
    throw new IOException(AVISO_SUP + " Use o upload manual do jar.");
}

private static void montarJape(Conexao conexao, ClassLoader loader) throws Exception {
    conexao.jape = loader.loadClass("br.com.sankhya.jape.core.JapeSession");
    conexao.handle = conexao.jape.getMethod("open").invoke(null);
    Object facade = loader.loadClass("br.com.sankhya.modelcore.util.EntityFacadeFactory")
                          .getMethod("getDWFFacade").invoke(null);
    conexao.jdbc = loader.loadClass("br.com.sankhya.jape.EntityFacade")
                         .getMethod("getJdbcWrapper").invoke(facade);
    Class<?> wrapper = loader.loadClass("br.com.sankhya.jape.dao.JdbcWrapper");
    wrapper.getMethod("openSession").invoke(conexao.jdbc);
    conexao.conn = (Connection) wrapper.getMethod("getConnection").invoke(conexao.jdbc);
    conexao.origem = "JAPE " + wrapper.getMethod("getDSJndiName").invoke(conexao.jdbc);
}

private static Conexao porJape() throws Exception {
    Conexao conexao = new Conexao();
    try {
        montarJape(conexao, Thread.currentThread().getContextClassLoader());
        return conexao;
    } catch (Exception semJape) {
        fechar(conexao);
        throw semJape;
    }
}

private static Conexao porJndi(String nome) throws Exception {
    Conexao conexao = new Conexao();
    DataSource fonte = (DataSource) new InitialContext().lookup(nome);
    conexao.conn = fonte.getConnection();
    conexao.origem = "JNDI " + nome;
    return conexao;
}

private static Conexao porCandidatos() throws Exception {
    Throwable ultimo = null;
    try {
        return porJape();
    } catch (Throwable semJape) {
        ultimo = semJape;
    }
    for (int i = 0; i < DS_JNDI.length; i++) {
        try { return porJndi(DS_JNDI[i]); } catch (Throwable naoResolveu) { ultimo = naoResolveu; }
    }
    throw new IOException("Sem conexao com o banco: " + descrever(ultimo));
}

private static Conexao abrirConexao() throws Exception {
    String forcado = System.getProperty("jvexplorer.ds");
    Conexao conexao = (forcado == null || forcado.trim().length() == 0)
                    ? porCandidatos() : porJndi(forcado.trim());
    try {
        String vendor = conexao.conn.getMetaData().getDatabaseProductName();
        conexao.oracle = vendor != null && vendor.toUpperCase(Locale.ENGLISH).indexOf("ORACLE") >= 0;
    } catch (SQLException semMetadados) {
        fechar(conexao);
        throw semMetadados;
    }
    origemBanco = conexao.origem;
    return conexao;
}

private static void fechar(Conexao conexao) {
    if (conexao == null) return;
    try {
        /* closeSession devolve a conexao ao pool do JAPE; fora dele o close e nosso. */
        if (conexao.jdbc != null) conexao.jdbc.getClass().getMethod("closeSession").invoke(conexao.jdbc);
        else if (conexao.conn != null) conexao.conn.close();
    } catch (Throwable ignorado) { }
    try {
        if (conexao.handle != null) {
            conexao.jape.getMethod("close", conexao.handle.getClass()).invoke(null, conexao.handle);
        }
    } catch (Throwable ignorado) { }
}

private static void encerrar(ResultSet rs, Statement comando, Conexao conexao) {
    try { if (rs != null) rs.close(); } catch (SQLException ignorado) { }
    try { if (comando != null) comando.close(); } catch (SQLException ignorado) { }
    fechar(conexao);
}

/* LIKE com curingas do usuario escapados: '_' solto casaria pacotes demais. */
private static String curinga(String termo) {
    String limpo = termo == null ? "" : termo.trim().toUpperCase(Locale.ENGLISH);
    limpo = limpo.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_");
    return "%" + limpo + "%";
}

private static int inteiro(String valor) throws IOException {
    try {
        return Integer.parseInt(valor.trim());
    } catch (RuntimeException invalido) {
        throw new IOException("Parametro numerico invalido: " + valor);
    }
}

private static String sqlJars(boolean oracle) {
    return "SELECT J.CODJAR, J.DESCRICAO, "
         + (oracle ? "DBMS_LOB.GETLENGTH(J.ARQUIVO)" : "DATALENGTH(J.ARQUIVO)")
         + " TAMANHO FROM TSIJAR J WHERE J.CODMODULO = ? ORDER BY J.CODJAR";
}

private static void linhaModulo(StringBuilder sb, ResultSet rs) throws SQLException {
    sb.append("{\"cod\":").append(rs.getInt("CODMODULO"))
      .append(",\"descr\":\"").append(escapeJson(rs.getString("DESCRMODULO")))
      .append("\",\"pacote\":\"").append(escapeJson(rs.getString("RESOURCEID")))
      .append("\",\"jars\":").append(rs.getInt("QTDJAR")).append('}');
}

private static String jsonModulos(String termo) throws Exception {
    StringBuilder sb = new StringBuilder(512).append("{\"success\":true,\"modulos\":[");
    Conexao conexao = abrirConexao();
    PreparedStatement comando = null;
    ResultSet rs = null;
    try {
        comando = conexao.conn.prepareStatement(SQL_MODULOS);
        comando.setString(1, curinga(termo));
        comando.setString(2, curinga(termo));
        rs = comando.executeQuery();
        for (int i = 0; rs.next(); i++) {
            if (i > 0) sb.append(',');
            linhaModulo(sb, rs);
        }
    } finally {
        encerrar(rs, comando, conexao);
    }
    return sb.append("]}").toString();
}

private static String jsonJars(int codModulo) throws Exception {
    StringBuilder sb = new StringBuilder(256).append("{\"success\":true,\"jars\":[");
    Conexao conexao = abrirConexao();
    PreparedStatement comando = null;
    ResultSet rs = null;
    try {
        comando = conexao.conn.prepareStatement(sqlJars(conexao.oracle));
        comando.setInt(1, codModulo);
        rs = comando.executeQuery();
        for (int i = 0; rs.next(); i++) {
            if (i > 0) sb.append(',');
            sb.append("{\"cod\":").append(rs.getInt("CODJAR"))
              .append(",\"descricao\":\"").append(escapeJson(rs.getString("DESCRICAO")))
              .append("\",\"tamanho\":").append(rs.getLong("TAMANHO")).append('}');
        }
    } finally {
        encerrar(rs, comando, conexao);
    }
    return sb.append("]}").toString();
}

private static String testarConexao() {
    if (origemBanco.length() > 0) return origemBanco;
    Conexao conexao = null;
    try {
        conexao = abrirConexao();
        return conexao.origem;
    } catch (Throwable falha) {
        return "falhou: " + descrever(falha);
    } finally {
        fechar(conexao);
    }
}

private static String usuarioDe(Object autenticacao) {
    if (autenticacao == null) return "";
    try {
        return "CODUSU " + autenticacao.getClass().getMethod("getUserID").invoke(autenticacao);
    } catch (Throwable semUsuario) {
        return autenticacao.getClass().getName();
    }
}

/* Listado no Diagnostico para explicar um SUP que o JSP nao consegue reconhecer. */
private static String jsonAtributosSessao(HttpSession sessao) {
    StringBuilder sb = new StringBuilder(256).append('[');
    Enumeration<String> nomes = sessao.getAttributeNames();
    boolean primeiro = true;
    while (nomes.hasMoreElements()) {
        String nome = nomes.nextElement();
        Object valor = sessao.getAttribute(nome);
        if (!primeiro) sb.append(',');
        primeiro = false;
        sb.append('"').append(escapeJson(nome)).append(" = ")
          .append(escapeJson(valor == null ? "null" : valor.getClass().getName())).append('"');
    }
    return sb.append(']').toString();
}

private static String jsonBanco(HttpSession sessao) {
    StringBuilder onde = new StringBuilder("ausente");
    Object atual = autenticacao(sessao, onde);
    boolean sup = ehSup(sessao);
    return new StringBuilder(256)
        .append("{\"sup\":").append(sup)
        .append(",\"auth\":\"").append(escapeJson(onde.toString()))
        .append("\",\"usuario\":\"").append(escapeJson(usuarioDe(atual)))
        .append("\",\"conexao\":\"").append(escapeJson(sup ? testarConexao() : ""))
        .append("\",\"sessao\":").append(jsonAtributosSessao(sessao))
        .append('}').toString();
}

private static String nomeJarDe(String descricao, int codModulo, int codJar) {
    String base = descricao == null ? "" : nomeSimples(descricao.replace('\\', '/')).trim();
    if (base.length() == 0) return "modulo" + codModulo + "-jar" + codJar + ".jar";
    return base.toLowerCase(Locale.ENGLISH).endsWith(".jar") ? base : base + ".jar";
}

/* Grava o BLOB no arquivo parcial da sessao, reaproveitando o teto do upload. */
private static void baixarJar(Estado estado, int codModulo, int codJar) throws Exception {
    Conexao conexao = abrirConexao();
    PreparedStatement comando = null;
    ResultSet rs = null;
    try {
        comando = conexao.conn.prepareStatement(SQL_JAR);
        comando.setInt(1, codModulo);
        comando.setInt(2, codJar);
        rs = comando.executeQuery();
        if (!rs.next()) throw new IOException("Jar " + codJar + " do modulo " + codModulo + " nao existe na base.");
        String descricao = rs.getString("DESCRICAO");
        estado.rotulo = rs.getString("DESCRMODULO") + " / " + descricao;
        estado.nomeJar = nomeJarDe(descricao, codModulo, codJar);
        estado.codModulo = codModulo;
        estado.codJar = codJar;
        InputStream in = rs.getBinaryStream("ARQUIVO");
        if (in == null) throw new IOException("O jar esta cadastrado sem conteudo (TSIJAR.ARQUIVO nulo).");
        try { anexar(estado.parcial, in, 0L); } finally { in.close(); }
    } finally {
        encerrar(rs, comando, conexao);
    }
}

private static void abrirDaBase(Estado estado, int codModulo, int codJar) throws Exception {
    limpar(estado);
    estado.dir.mkdirs();
    baixarJar(estado, codModulo, codJar);
    validarAssinatura(estado.parcial);
    if (!estado.parcial.renameTo(estado.jar)) {
        throw new IOException("Nao foi possivel gravar o jar no diretorio temporario da sessao.");
    }
    estado.tamanhoJar = estado.jar.length();
    indexar(estado, extrairTudo(estado));
}

/* ------------------------------------------------------------- download */

/* filename so aceita ASCII sem aspas; o nome original segue em filename* (RFC 5987). */
private static String dispositionDe(String nome) throws UnsupportedEncodingException {
    String base = nome == null || nome.length() == 0 ? "arquivo.jar" : nome;
    String ascii = base.replaceAll("[^A-Za-z0-9._-]", "_");
    String codificado = URLEncoder.encode(base, "UTF-8").replace("+", "%20");
    return "attachment; filename=\"" + ascii + "\"; filename*=UTF-8''" + codificado;
}

/* Entrega so o jar ja carregado na sessao: a permissao foi checada ao abrir. */
private static void enviarJar(Estado estado, HttpServletResponse resposta) throws IOException {
    resposta.setContentType("application/java-archive");
    resposta.setHeader("Content-Disposition", dispositionDe(estado.nomeJar));
    resposta.setHeader("Content-Length", String.valueOf(estado.jar.length()));
    resposta.setHeader("Cache-Control", "no-cache, no-store, must-revalidate");
    InputStream in = new BufferedInputStream(new FileInputStream(estado.jar));
    OutputStream saida = resposta.getOutputStream();
    try {
        byte[] buf = new byte[BUFFER];
        int lidos;
        while ((lidos = in.read(buf)) != -1) saida.write(buf, 0, lidos);
        saida.flush();
    } finally {
        in.close();
    }
}

/* --------------------------------------------------------------- upload */

private static void anexar(File destino, InputStream in, long jaGravado) throws IOException {
    OutputStream out = new BufferedOutputStream(new FileOutputStream(destino, true));
    long total = jaGravado;
    try {
        byte[] buf = new byte[BUFFER];
        int lidos;
        while ((lidos = in.read(buf)) != -1) {
            total += lidos;
            if (total > MAX_JAR) throw new IOException("O arquivo excede o limite de " + (MAX_JAR / 1048576L) + " MB.");
            out.write(buf, 0, lidos);
        }
    } finally {
        out.close();
    }
}

private static void validarAssinatura(File arquivo) throws IOException {
    InputStream in = new FileInputStream(arquivo);
    try {
        byte[] magico = new byte[4];
        boolean ok = in.read(magico) == 4 && magico[0] == 'P' && magico[1] == 'K'
                  && magico[2] == 3 && magico[3] == 4;
        if (!ok) throw new IOException("O arquivo enviado nao e um .jar valido.");
    } finally {
        in.close();
    }
}

/* Bloqueia zip-slip: nomes absolutos ou com travessia sao descartados. */
private static String nomeSeguro(String nome) {
    String limpo = nome.replace('\\', '/');
    if (limpo.length() == 0) return null;
    if (limpo.startsWith("/") || limpo.contains("../") || limpo.contains(":")) return null;
    return limpo;
}

private static long copiarEntrada(JarFile jar, JarEntry entrada, File destino) throws IOException {
    destino.getParentFile().mkdirs();
    InputStream in = jar.getInputStream(entrada);
    OutputStream out = new BufferedOutputStream(new FileOutputStream(destino));
    long total = 0;
    try {
        byte[] buf = new byte[BUFFER];
        int lidos;
        while ((lidos = in.read(buf)) != -1) {
            out.write(buf, 0, lidos);
            total += lidos;
        }
    } finally {
        out.close();
        in.close();
    }
    return total;
}

private static List<String> extrairTudo(Estado estado) throws IOException {
    List<String> nomes = new ArrayList<String>();
    JarFile jar = new JarFile(estado.jar);
    try {
        long escrito = 0;
        Enumeration<JarEntry> entradas = jar.entries();
        while (entradas.hasMoreElements()) {
            JarEntry entrada = entradas.nextElement();
            if (nomes.size() >= MAX_ENTRADAS) throw new IOException("JAR com mais de " + MAX_ENTRADAS + " entradas.");
            String nome = entrada.isDirectory() ? null : nomeSeguro(entrada.getName());
            if (nome == null) continue;
            escrito += copiarEntrada(jar, entrada, new File(estado.classes, nome));
            if (escrito > MAX_EXPLODIDO) throw new IOException("O conteudo extraido excede o limite permitido.");
            nomes.add(nome);
        }
    } finally {
        jar.close();
    }
    return nomes;
}

/* ---------------------------------------------------------------- indice */

private static String chaveFonte(String nome) {
    for (String raiz : RAIZES_FONTE) {
        if (nome.startsWith(raiz)) return nome.substring(raiz.length());
        int pos = nome.indexOf("/" + raiz);
        if (pos >= 0) return nome.substring(pos + raiz.length() + 1);
    }
    return nome;
}

private static Map<String, String> mapaFontes(List<String> nomes) {
    Map<String, String> fontes = new HashMap<String, String>();
    for (String nome : nomes) {
        if (!nome.endsWith(".java") && !nome.endsWith(".kt")) continue;
        fontes.put(chaveFonte(nome), nome);
    }
    return fontes;
}

private static void indexarClasse(Estado estado, String nome, Map<String, String> fontes) {
    if (nomeSimples(nome).indexOf('$') >= 0) return;
    String path = nome.substring(0, nome.length() - 6) + ".java";
    No no = new No();
    no.path = path;
    no.tipo = "class";
    no.classe = new File(estado.classes, nome);
    no.tamanho = no.classe.length();
    String fonte = fontes.get(path);
    if (fonte == null) fonte = fontes.get(path.substring(0, path.length() - 5) + ".kt");
    no.origem = fonte == null ? "dec" : "src";
    if (fonte != null) no.arquivo = new File(estado.classes, fonte);
    estado.indice.put(path, no);
    estado.qtdClasses++;
}

private static void indexarArquivo(Estado estado, String nome) {
    No no = new No();
    no.path = nome;
    no.arquivo = new File(estado.classes, nome);
    no.tamanho = no.arquivo.length();
    no.tipo = EXT_TEXTO.contains(ext(nome)) ? "text" : "bin";
    no.origem = "arq";
    estado.indice.put(nome, no);
}

private static void indexar(Estado estado, List<String> nomes) {
    Map<String, String> fontes = mapaFontes(nomes);
    Set<String> consumidos = new HashSet<String>(fontes.values());
    for (String nome : nomes) {
        if (nome.endsWith(".class")) indexarClasse(estado, nome, fontes);
        else if (!consumidos.contains(nome)) indexarArquivo(estado, nome);
    }
    estado.qtdEntradas = nomes.size();
}

/* ------------------------------------------------------------------ CFR */

private static void adicionarReal(ServletContext contexto, List<String> candidatos, String caminho) {
    String real = contexto.getRealPath(caminho);
    if (real != null && !candidatos.contains(real)) candidatos.add(real);
}

private static List<String> candidatosCfr(ServletContext contexto, HttpServletRequest requisicao) {
    List<String> candidatos = new ArrayList<String>();
    String propriedade = System.getProperty("jvexplorer.cfr.jar");
    if (propriedade != null && propriedade.trim().length() > 0) candidatos.add(propriedade.trim());
    String meuPath = requisicao.getServletPath();
    // Pasta do proprio JSP: "" quando ele esta na raiz do contexto (lastIndexOf == 0).
    String pasta = (meuPath == null || meuPath.lastIndexOf('/') < 0)
                 ? "" : meuPath.substring(0, meuPath.lastIndexOf('/'));
    adicionarReal(contexto, candidatos, pasta + "/lib");
    adicionarReal(contexto, candidatos, pasta.length() == 0 ? "/" : pasta);
    adicionarReal(contexto, candidatos, "/dashboard");
    candidatos.add(new File(System.getProperty("java.io.tmpdir"), "jvexplorer-lib").getAbsolutePath());
    return candidatos;
}

private static File buscarJar(File dir, int profundidade) {
    if (profundidade < 0 || dir == null || !dir.isDirectory()) return null;
    File[] filhos = dir.listFiles();
    if (filhos == null) return null;
    for (File filho : filhos) {
        String nome = filho.getName().toLowerCase(Locale.ENGLISH);
        if (filho.isFile() && nome.startsWith("cfr") && nome.endsWith(".jar")) return filho;
    }
    for (File filho : filhos) {
        File achado = filho.isDirectory() ? buscarJar(filho, profundidade - 1) : null;
        if (achado != null) return achado;
    }
    return null;
}

private static File acharCfr(ServletContext contexto, HttpServletRequest requisicao) {
    String memorizado = cfrPath;
    if (memorizado != null && new File(memorizado).isFile()) return new File(memorizado);
    for (String candidato : candidatosCfr(contexto, requisicao)) {
        File alvo = new File(candidato);
        File achado = alvo.isFile() && alvo.getName().toLowerCase(Locale.ENGLISH).endsWith(".jar")
                    ? alvo : buscarJar(alvo, 4);
        if (achado != null) {
            cfrPath = achado.getAbsolutePath();
            return achado;
        }
    }
    return null;
}

private static synchronized ClassLoader loaderCfr(File cfrJar) throws MalformedURLException {
    if (cfrLoader == null) {
        cfrLoader = new URLClassLoader(new URL[]{ cfrJar.toURI().toURL() },
                                       Thread.currentThread().getContextClassLoader());
    }
    return cfrLoader;
}

private static void rodarCfrApi(ClassLoader loader, File classe, Map<String, String> opcoes) throws Exception {
    Class<?> builder = loader.loadClass("org.benf.cfr.reader.api.CfrDriver$Builder");
    Object instancia = builder.newInstance();
    instancia = builder.getMethod("withOptions", Map.class).invoke(instancia, opcoes);
    Object driver = builder.getMethod("build").invoke(instancia);
    driver.getClass().getMethod("analyse", List.class)
          .invoke(driver, Collections.singletonList(classe.getAbsolutePath()));
}

private static void rodarCfrMain(ClassLoader loader, File classe, Map<String, String> opcoes) throws Exception {
    String[] argumentos = new String[]{
        classe.getAbsolutePath(),
        "--outputdir", opcoes.get("outputdir"),
        "--extraclasspath", opcoes.get("extraclasspath") };
    loader.loadClass("org.benf.cfr.reader.Main")
          .getMethod("main", String[].class)
          .invoke(null, (Object) argumentos);
}

private static void rodarCfr(File cfrJar, File classe, File classpath, File saida) throws Exception {
    ClassLoader loader = loaderCfr(cfrJar);
    Map<String, String> opcoes = new LinkedHashMap<String, String>();
    opcoes.put("outputdir", saida.getAbsolutePath());
    opcoes.put("extraclasspath", classpath.getAbsolutePath());
    opcoes.put("silent", "true");
    try {
        rodarCfrApi(loader, classe, opcoes);
    } catch (ClassNotFoundException semApiPublica) {
        rodarCfrMain(loader, classe, opcoes);
    } catch (Exception falha) {
        /* Versao de CFR sem a opcao 'silent': repete com o conjunto minimo. */
        opcoes.remove("silent");
        rodarCfrApi(loader, classe, opcoes);
    }
}

private static File acharJava(File dir, String desejado) {
    if (dir == null || !dir.isDirectory()) return null;
    File[] filhos = dir.listFiles();
    if (filhos == null) return null;
    File alternativo = null;
    for (File filho : filhos) {
        File achado = filho.isDirectory() ? acharJava(filho, desejado) : filho;
        if (achado == null || !achado.getName().endsWith(".java")) continue;
        if (achado.getName().equals(desejado)) return achado;
        if (alternativo == null) alternativo = achado;
    }
    return alternativo;
}

private static String descompilar(Estado estado, No no, File cfrJar) throws Exception {
    File saida = new File(estado.saida, "d" + (++estado.seq));
    rodarCfr(cfrJar, no.classe, estado.classes, saida);
    File gerado = acharJava(saida, nomeSimples(no.path));
    if (gerado == null) throw new IOException("O CFR nao produziu fonte para esta classe.");
    return lerTexto(gerado);
}

/* --------------------------------------------------------------- analise */

/* Analise estatica: o classfile e lido direto, sem carregar nem descompilar.
   Nada do jar executa e dependencias ausentes nao impedem a leitura. */
private static final int MAGICO_CLASSE = 0xCAFEBABE;
private static final int CP_UTF8 = 1, CP_INT = 3, CP_FLOAT = 4, CP_LONG = 5, CP_DOUBLE = 6,
    CP_CLASSE = 7, CP_STRING = 8, CP_CAMPO = 9, CP_METODO = 10, CP_METODO_IF = 11,
    CP_NOME_TIPO = 12, CP_HANDLE = 15, CP_TIPO_METODO = 16, CP_DINAMICO = 17,
    CP_INVOKEDYNAMIC = 18, CP_MODULO = 19, CP_PACOTE = 20;
private static final int ACC_PUBLIC = 0x0001, ACC_SYNTHETIC = 0x1000;
private static final int MAX_LISTA = 20;
private static final int MAX_HERANCA = 10;
private static final int MIN_ENTIDADE = 5;
private static final String PAPEL_APOIO = "Apoio";

/* Papel pelo nome simples: o pacote da API muda entre versoes do Sankhya. */
private static final Map<String, String> PAPEIS = new HashMap<String, String>();
static {
    PAPEIS.put("EventoProgramavelJava", "Evento programavel");
    PAPEIS.put("AcaoRotinaJava", "Botao de acao");
    PAPEIS.put("ScheduledAction", "Acao agendada");
    PAPEIS.put("RegraNegocioJava", "Regra de negocio");
    PAPEIS.put("ActionButton", "Botao de acao (addon)");
    PAPEIS.put("Listener", "Listener (addon)");
    PAPEIS.put("Job", "Job (addon)");
    PAPEIS.put("BusinessRule", "Regra de negocio (addon)");
    PAPEIS.put("Callback", "Callback (addon)");
    PAPEIS.put("SessionBean", "EJB");
    PAPEIS.put("Stateless", "EJB");
    PAPEIS.put("Stateful", "EJB");
}

private static final String[] DONOS_DADOS = { "br/com/sankhya/jape/", "java/sql/" };
private static final Set<String> API_ESCRITA = new HashSet<String>(Arrays.asList(
    "create", "createEntity", "prepareToUpdate", "prepareToUpdateByPK", "update", "save",
    "delete", "deleteByCriteria", "removeEntity", "executeUpdate", "saveOrUpdateEntity"));
private static final Set<String> API_LEITURA = new HashSet<String>(Arrays.asList(
    "find", "findByPK", "findOne", "findEntityByPrimaryKey", "findByDynamicFinder",
    "findByDynamicFinderAsVO", "executeQuery"));

/* Tabelas so no padrao Sankhya (T??/V?? + AD_): evita ler "update dos itens" como tabela. */
private static final String RE_TABELA = "((?:AD_\\w+)|(?:[TV][A-Z]{2}\\w{2,}))";
private static final Pattern RE_LEITURA = Pattern.compile(
    "(?i)(?<!DELETE\\s)\\b(?:FROM|JOIN)\\s+" + RE_TABELA);
private static final Pattern RE_ESCRITA = Pattern.compile(
    "(?i)\\b(?:INSERT\\s+INTO|UPDATE|DELETE\\s+FROM|MERGE\\s+INTO)\\s+" + RE_TABELA);
/* "from X" solto aparece em textos de ajuda: leitura so conta se a classe tem SELECT. */
private static final Pattern RE_SELECT = Pattern.compile("(?i)\\bSELECT\\b");
private static final Pattern RE_ENTIDADE = Pattern.compile("^(?:[A-Z][a-z0-9]+){1,6}$|^AD[A-Z0-9]{3,}$");
private static final Set<String> NAO_TABELA = new HashSet<String>(Arrays.asList(
    "TABLE", "TEMP", "TEMPORARY", "TRIGGER", "VALUES"));

public static final class Pool {
    int[] tag;
    int[] a;
    int[] b;
    String[] utf;

    String utf(int i) { return i > 0 && i < utf.length && utf[i] != null ? utf[i] : ""; }
    String classe(int i) { return utf(a[i]); }
    String membro(int i) { return classe(a[i]) + "#" + utf(a[b[i]]); }
}

public static final class InfoClasse {
    String nome = "";
    String superClasse = "";
    final List<String> interfaces = new ArrayList<String>();
    final Set<String> metodos = new LinkedHashSet<String>();
    final Set<String> classes = new LinkedHashSet<String>();
    final Set<String> descritores = new HashSet<String>();
    final Set<String> chamadas = new HashSet<String>();
    final List<String> textos = new ArrayList<String>();
}

public static final class Coleta {
    final Map<String, InfoClasse> classes = new TreeMap<String, InfoClasse>();
    int falhas;
}

public static final class Ficha {
    String path;
    String papel;
    InfoClasse info;
    boolean gravaApi;
    boolean leApi;
    final Set<String> leitura = new TreeSet<String>();
    final Set<String> escrita = new TreeSet<String>();
    final Set<String> entidades = new TreeSet<String>();
    final Set<String> apis = new TreeSet<String>();
    final Set<String> dependencias = new TreeSet<String>();
}

/* skipBytes pode pular menos que o pedido: insiste ate o fim ou acusa truncamento. */
private static void pular(DataInputStream in, int bytes) throws IOException {
    int faltam = bytes;
    while (faltam > 0) {
        int pulados = in.skipBytes(faltam);
        if (pulados <= 0) throw new EOFException("Classfile truncado.");
        faltam -= pulados;
    }
}

private static void lerEntrada(DataInputStream in, Pool pool, int i, int tag) throws IOException {
    switch (tag) {
        case CP_UTF8: pool.utf[i] = in.readUTF(); break;
        case CP_INT: case CP_FLOAT: pular(in, 4); break;
        case CP_HANDLE: pular(in, 3); break;
        case CP_CLASSE: case CP_STRING: case CP_TIPO_METODO: case CP_MODULO: case CP_PACOTE:
            pool.a[i] = in.readUnsignedShort(); break;
        case CP_CAMPO: case CP_METODO: case CP_METODO_IF: case CP_NOME_TIPO:
        case CP_DINAMICO: case CP_INVOKEDYNAMIC:
            pool.a[i] = in.readUnsignedShort();
            pool.b[i] = in.readUnsignedShort();
            break;
        default: throw new IOException("Tag de constant pool desconhecida: " + tag);
    }
}

private static Pool lerPool(DataInputStream in) throws IOException {
    int total = in.readUnsignedShort();
    Pool pool = new Pool();
    pool.tag = new int[total];
    pool.a = new int[total];
    pool.b = new int[total];
    pool.utf = new String[total];
    for (int i = 1; i < total; i++) {
        int tag = in.readUnsignedByte();
        pool.tag[i] = tag;
        if (tag != CP_LONG && tag != CP_DOUBLE) {
            lerEntrada(in, pool, i, tag);
            continue;
        }
        pular(in, 8);
        i++; // long e double ocupam duas posicoes do pool
    }
    return pool;
}

private static void pularAtributos(DataInputStream in) throws IOException {
    int qtd = in.readUnsignedShort();
    for (int i = 0; i < qtd; i++) {
        pular(in, 2);
        pular(in, in.readInt());
    }
}

private static void pularCampos(DataInputStream in) throws IOException {
    int qtd = in.readUnsignedShort();
    for (int i = 0; i < qtd; i++) {
        pular(in, 6);
        pularAtributos(in);
    }
}

private static void lerMetodos(DataInputStream in, Pool pool, InfoClasse info) throws IOException {
    int qtd = in.readUnsignedShort();
    for (int i = 0; i < qtd; i++) {
        int acesso = in.readUnsignedShort();
        String nome = pool.utf(in.readUnsignedShort());
        pular(in, 2);
        pularAtributos(in);
        boolean publico = (acesso & ACC_PUBLIC) != 0 && (acesso & ACC_SYNTHETIC) == 0;
        if (publico && !nome.startsWith("<") && !nome.startsWith("lambda$")) info.metodos.add(nome);
    }
}

private static void extrairPool(Pool pool, InfoClasse info) {
    for (int i = 1; i < pool.tag.length; i++) {
        int tag = pool.tag[i];
        if (tag == CP_CLASSE) info.classes.add(pool.classe(i));
        else if (tag == CP_STRING) info.textos.add(pool.utf(pool.a[i]));
        else if (tag == CP_METODO || tag == CP_METODO_IF) info.chamadas.add(pool.membro(i));
        else if (tag == CP_UTF8 && pool.utf[i].startsWith("L") && pool.utf[i].endsWith(";")) {
            info.descritores.add(pool.utf[i].substring(1, pool.utf[i].length() - 1));
        }
    }
}

private static InfoClasse lerClasse(File arquivo) throws IOException {
    DataInputStream in = new DataInputStream(new BufferedInputStream(new FileInputStream(arquivo)));
    try {
        if (in.readInt() != MAGICO_CLASSE) throw new IOException("Classfile invalido: " + arquivo.getName());
        pular(in, 4); // minor + major
        Pool pool = lerPool(in);
        InfoClasse info = new InfoClasse();
        pular(in, 2); // access flags
        info.nome = pool.classe(in.readUnsignedShort());
        int indiceSuper = in.readUnsignedShort();
        info.superClasse = indiceSuper == 0 ? "" : pool.classe(indiceSuper);
        int qtd = in.readUnsignedShort();
        for (int i = 0; i < qtd; i++) info.interfaces.add(pool.classe(in.readUnsignedShort()));
        pularCampos(in);
        lerMetodos(in, pool, info);
        extrairPool(pool, info);
        return info;
    } finally {
        in.close();
    }
}

/* Classes internas ($) somam na externa: o SQL de um callback anonimo e da classe dona. */
private static void incorporar(InfoClasse acumulado, InfoClasse lida, boolean principal) {
    if (principal) {
        acumulado.nome = lida.nome;
        acumulado.superClasse = lida.superClasse;
        acumulado.interfaces.addAll(lida.interfaces);
        acumulado.metodos.addAll(lida.metodos);
    }
    acumulado.classes.addAll(lida.classes);
    acumulado.descritores.addAll(lida.descritores);
    acumulado.chamadas.addAll(lida.chamadas);
    acumulado.textos.addAll(lida.textos);
}

private static String simplesDe(String nomeInterno) {
    String nome = nomeInterno.substring(nomeInterno.lastIndexOf('/') + 1);
    return nome.substring(nome.lastIndexOf('$') + 1);
}

private static String pathDe(String nomeInterno) {
    int inicioNome = nomeInterno.lastIndexOf('/') + 1;
    int cifrao = nomeInterno.indexOf('$', inicioNome);
    return (cifrao < 0 ? nomeInterno : nomeInterno.substring(0, cifrao)) + ".java";
}

private static void incorporarArquivo(File arquivo, String rel, Coleta coleta) {
    String semExtensao = rel.substring(0, rel.length() - ".class".length());
    String path = pathDe(semExtensao);
    InfoClasse lida;
    try {
        lida = lerClasse(arquivo);
    } catch (Exception ilegivel) {
        coleta.falhas++;
        return;
    }
    InfoClasse acumulado = coleta.classes.get(path);
    if (acumulado == null) {
        acumulado = new InfoClasse();
        coleta.classes.put(path, acumulado);
    }
    incorporar(acumulado, lida, semExtensao.indexOf('$', semExtensao.lastIndexOf('/') + 1) < 0);
}

private static void coletarClasses(File dir, String prefixo, Coleta coleta) {
    File[] filhos = dir.listFiles();
    if (filhos == null) return;
    for (File filho : filhos) {
        String rel = prefixo + filho.getName();
        if (filho.isDirectory()) coletarClasses(filho, rel + "/", coleta);
        else if (rel.endsWith(".class") && !rel.startsWith("META-INF/")) incorporarArquivo(filho, rel, coleta);
    }
}

private static String papelDireto(InfoClasse info) {
    List<String> tipos = new ArrayList<String>(info.interfaces);
    tipos.add(info.superClasse);
    tipos.addAll(info.descritores);
    for (String tipo : tipos) {
        String papel = PAPEIS.get(simplesDe(tipo));
        if (papel != null) return papel;
    }
    return null;
}

/* Sobe a heranca dentro do jar: uma base abstrata pode ser quem implementa a interface Sankhya. */
private static String papelDe(InfoClasse info, Coleta coleta) {
    InfoClasse atual = info;
    for (int nivel = 0; atual != null && nivel < MAX_HERANCA; nivel++) {
        String papel = papelDireto(atual);
        if (papel != null) return papel;
        atual = atual.superClasse.length() == 0 ? null : coleta.classes.get(pathDe(atual.superClasse));
    }
    return PAPEL_APOIO;
}

private static void tabelas(Pattern re, String sql, Set<String> destino) {
    Matcher achado = re.matcher(sql);
    while (achado.find()) {
        String tabela = achado.group(1).toUpperCase(Locale.ENGLISH);
        if (!NAO_TABELA.contains(tabela)) destino.add(tabela);
    }
}

private static boolean ehDonoDeDados(String dono) {
    for (String prefixo : DONOS_DADOS) {
        if (dono.startsWith(prefixo)) return true;
    }
    return false;
}

private static void classificarChamadas(InfoClasse info, Ficha ficha) {
    for (String chamada : info.chamadas) {
        int corte = chamada.indexOf('#');
        if (!ehDonoDeDados(chamada.substring(0, corte))) continue;
        String metodo = chamada.substring(corte + 1);
        if (API_ESCRITA.contains(metodo)) ficha.gravaApi = true;
        else if (API_LEITURA.contains(metodo)) ficha.leApi = true;
    }
}

private static void classificarReferencias(InfoClasse info, Coleta coleta, Ficha ficha) {
    for (String nome : info.classes) {
        if (nome.startsWith("[")) continue;
        String path = pathDe(nome);
        if (coleta.classes.containsKey(path)) {
            if (!path.equals(ficha.path)) ficha.dependencias.add(path);
        } else if (nome.startsWith("br/com/sankhya/") || nome.startsWith("com/sankhya/")) {
            ficha.apis.add(simplesDe(nome));
        }
    }
}

/* Nomes de entidade costumam ser constantes inlinadas pelo javac: so da para inferir pelo literal. */
private static void entidadesProvaveis(InfoClasse info, Ficha ficha) {
    boolean usaJape = false;
    for (String nome : info.classes) usaJape |= nome.startsWith("br/com/sankhya/jape/");
    if (!usaJape) return;
    for (String texto : info.textos) {
        if (texto.length() >= MIN_ENTIDADE && RE_ENTIDADE.matcher(texto).matches()) ficha.entidades.add(texto);
    }
}

private static String juntar(List<String> textos) {
    StringBuilder sb = new StringBuilder(256);
    for (String texto : textos) sb.append(texto).append(' ');
    return sb.toString();
}

private static Ficha montarFicha(String path, InfoClasse info, Coleta coleta) {
    Ficha ficha = new Ficha();
    ficha.path = path;
    ficha.info = info;
    ficha.papel = papelDe(info, coleta);
    String sql = juntar(info.textos);
    tabelas(RE_ESCRITA, sql, ficha.escrita);
    if (RE_SELECT.matcher(sql).find()) tabelas(RE_LEITURA, sql, ficha.leitura);
    classificarChamadas(info, ficha);
    classificarReferencias(info, coleta, ficha);
    entidadesProvaveis(info, ficha);
    return ficha;
}

/* Pontos de entrada (eventos, botoes, jobs) primeiro; classes de apoio por ultimo. */
private static final Comparator<Ficha> ORDEM_FICHA = new Comparator<Ficha>() {
    public int compare(Ficha x, Ficha y) {
        boolean apoioX = PAPEL_APOIO.equals(x.papel);
        boolean apoioY = PAPEL_APOIO.equals(y.papel);
        if (apoioX != apoioY) return apoioX ? 1 : -1;
        int porPapel = x.papel.compareTo(y.papel);
        return porPapel != 0 ? porPapel : x.path.compareTo(y.path);
    }
};

private static String jsonLista(Collection<String> itens) {
    StringBuilder sb = new StringBuilder(64).append('[');
    int i = 0;
    for (String item : itens) {
        if (i == MAX_LISTA) {
            sb.append(",\"+").append(itens.size() - MAX_LISTA).append('"');
            break;
        }
        if (i++ > 0) sb.append(',');
        sb.append('"').append(escapeJson(item.replace('/', '.'))).append('"');
    }
    return sb.append(']').toString();
}

private static void jsonFicha(StringBuilder sb, Ficha ficha) {
    List<String> dependencias = new ArrayList<String>();
    for (String path : ficha.dependencias) dependencias.add(path.substring(0, path.length() - ".java".length()));
    sb.append("{\"path\":\"").append(escapeJson(ficha.path))
      .append("\",\"papel\":\"").append(escapeJson(ficha.papel))
      .append("\",\"super\":\"").append(escapeJson(ficha.info.superClasse.replace('/', '.')))
      .append("\",\"gravaApi\":").append(ficha.gravaApi)
      .append(",\"leApi\":").append(ficha.leApi)
      .append(",\"interfaces\":").append(jsonLista(ficha.info.interfaces))
      .append(",\"leitura\":").append(jsonLista(ficha.leitura))
      .append(",\"escrita\":").append(jsonLista(ficha.escrita))
      .append(",\"entidades\":").append(jsonLista(ficha.entidades))
      .append(",\"apis\":").append(jsonLista(ficha.apis))
      .append(",\"metodos\":").append(jsonLista(ficha.info.metodos))
      .append(",\"dependencias\":").append(jsonLista(dependencias))
      .append('}');
}

private static void somarTabelas(Map<String, int[]> totais, Set<String> tabelas, int coluna) {
    for (String tabela : tabelas) {
        int[] contagem = totais.get(tabela);
        if (contagem == null) totais.put(tabela, contagem = new int[2]);
        contagem[coluna]++;
    }
}

private static String jsonResumo(List<Ficha> fichas, Coleta coleta) {
    Map<String, Integer> papeis = new TreeMap<String, Integer>();
    Map<String, int[]> tabelas = new TreeMap<String, int[]>();
    for (Ficha ficha : fichas) {
        Integer qtd = papeis.get(ficha.papel);
        papeis.put(ficha.papel, qtd == null ? 1 : qtd + 1);
        somarTabelas(tabelas, ficha.leitura, 0);
        somarTabelas(tabelas, ficha.escrita, 1);
    }
    StringBuilder sb = new StringBuilder(512).append("{\"classes\":").append(fichas.size())
        .append(",\"falhas\":").append(coleta.falhas).append(",\"papeis\":{");
    int i = 0;
    for (Map.Entry<String, Integer> papel : papeis.entrySet()) {
        if (i++ > 0) sb.append(',');
        sb.append('"').append(escapeJson(papel.getKey())).append("\":").append(papel.getValue());
    }
    return sb.append("},\"tabelas\":").append(jsonTabelas(tabelas)).append('}').toString();
}

private static String jsonTabelas(Map<String, int[]> tabelas) {
    StringBuilder sb = new StringBuilder(256).append('[');
    int i = 0;
    for (Map.Entry<String, int[]> tabela : tabelas.entrySet()) {
        if (i++ > 0) sb.append(',');
        sb.append("{\"nome\":\"").append(escapeJson(tabela.getKey()))
          .append("\",\"leitura\":").append(tabela.getValue()[0])
          .append(",\"escrita\":").append(tabela.getValue()[1]).append('}');
    }
    return sb.append(']').toString();
}

private static boolean ehMetadado(String path) {
    return path.endsWith("module-info.java") || path.endsWith("package-info.java");
}

/* Cacheada na sessao: o jar nao muda ate ser trocado, e limpar() descarta a analise. */
private static String jsonAnalise(Estado estado) throws IOException {
    if (estado.analise != null) return estado.analise;
    if (!estado.jar.isFile()) throw new IOException("Nenhum jar carregado nesta sessao.");
    Coleta coleta = new Coleta();
    coletarClasses(estado.classes, "", coleta);
    List<Ficha> fichas = new ArrayList<Ficha>();
    for (Map.Entry<String, InfoClasse> classe : coleta.classes.entrySet()) {
        if (!ehMetadado(classe.getKey())) fichas.add(montarFicha(classe.getKey(), classe.getValue(), coleta));
    }
    Collections.sort(fichas, ORDEM_FICHA);
    StringBuilder sb = new StringBuilder(fichas.size() * 256 + 256);
    sb.append("{\"success\":true,\"resumo\":").append(jsonResumo(fichas, coleta)).append(",\"classes\":[");
    for (int i = 0; i < fichas.size(); i++) {
        if (i > 0) sb.append(',');
        jsonFicha(sb, fichas.get(i));
    }
    estado.analise = sb.append("]}").toString();
    return estado.analise;
}

/* ------------------------------------------------------------------ JSON */

private static String jsonItens(Estado estado) {
    StringBuilder sb = new StringBuilder(estado.indice.size() * 96);
    sb.append('[');
    boolean primeiro = true;
    for (No no : estado.indice.values()) {
        if (!primeiro) sb.append(',');
        primeiro = false;
        sb.append("{\"path\":\"").append(escapeJson(no.path))
          .append("\",\"tipo\":\"").append(no.tipo)
          .append("\",\"origem\":\"").append(no.origem)
          .append("\",\"tamanho\":").append(no.tamanho).append('}');
    }
    return sb.append(']').toString();
}

private static String jsonJar(Estado estado) {
    return new StringBuilder("{\"nome\":\"").append(escapeJson(estado.nomeJar))
        .append("\",\"rotulo\":\"").append(escapeJson(estado.rotulo))
        .append("\",\"codModulo\":").append(estado.codModulo)
        .append(",\"codJar\":").append(estado.codJar)
        .append(",\"tamanho\":").append(estado.tamanhoJar)
        .append(",\"classes\":").append(estado.qtdClasses)
        .append(",\"entradas\":").append(estado.qtdEntradas)
        .append(",\"itens\":").append(estado.indice.size())
        .append('}').toString();
}

private static String jsonErro(String mensagem) {
    return "{\"success\":false,\"error\":\"" + escapeJson(mensagem) + "\"}";
}
%>
<%
/* ===================== ROTEAMENTO: interface ou API ===================== */
String acao = request.getParameter("action");

if (acao == null || acao.trim().length() == 0) {
    String query = request.getQueryString();
    String urlMge = request.getRequestURI() + (query == null ? "" : "?" + query);
    // getServletPath() e relativo ao contexto: sem o contextPath o browser resolveria
    // a rota alternativa contra a raiz do host (/main.jsp em vez de /mge/main.jsp).
    String urlJsp = request.getContextPath() + request.getServletPath();
%>
<!DOCTYPE html>
<html lang="pt-BR">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>JVExplorer</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Archivo:wght@400;500;600&family=Familjen+Grotesk:wght@500;600;700&family=JetBrains+Mono:wght@400;500;700&display=swap">
<style>
:root{
  --ground:#101218;
  --surface:#171A21;
  --surface-2:#1D212A;
  --line:#2A2F3A;
  --line-soft:#232833;
  --ink:#E6E9F0;
  --ink-2:#A7AEBE;
  --ink-3:#767E90;
  --accent:#E8912F;
  --accent-ink:#F0A855;
  --accent-wash:#2A1F14;
  --ok:#5FBE8C;
  --ok-wash:#1B2E25;
  --crit:#E4796D;
  --crit-wash:#2C1A18;
  --info:#6BAEDC;
  --info-wash:#16242F;
  --gutter:#565E6E;
  --sel:#2A2118;
  --c-comment:#6C7486;
  --c-string:#8FC7A3;
  --c-key:#D290C8;
  --c-anno:#E8912F;
  --c-num:#8CBDE0;
  --c-type:#7FC6CE;
  --c-fn:#C8CEDC;
  --veil:rgba(6,8,12,.66);
  --shadow:0 1px 2px rgba(0,0,0,.4), 0 8px 24px rgba(0,0,0,.35);
}

/* Tema claro: aplicado por data-theme no <html>. O escuro segue sendo o padrao. */
:root[data-theme="light"]{
  --ground:#F4F5F8;
  --surface:#FFFFFF;
  --surface-2:#EEF0F5;
  --line:#DCDFE7;
  --line-soft:#E8EAF0;
  --ink:#191C23;
  --ink-2:#4A5162;
  --ink-3:#7A8296;
  --accent:#B45A12;
  --accent-ink:#8A4409;
  --accent-wash:#F6E7D6;
  --ok:#2C6F4F;
  --ok-wash:#DCEDE3;
  --crit:#A82920;
  --crit-wash:#F7E2E0;
  --info:#255E8C;
  --info-wash:#DEE9F3;
  --gutter:#A6AEBF;
  --sel:#F0E2D2;
  --c-comment:#7B8494;
  --c-string:#2C6F4F;
  --c-key:#9C3A8C;
  --c-anno:#B45A12;
  --c-num:#255E8C;
  --c-type:#1F5C6B;
  --c-fn:#3B4252;
  --veil:rgba(30,34,44,.38);
  --shadow:0 1px 2px rgba(20,22,27,.07), 0 8px 24px rgba(20,22,27,.06);
}

*{box-sizing:border-box}
html,body{height:100%}
body{
  margin:0; background:var(--ground); color:var(--ink);
  font-family:"Archivo","Helvetica Neue",Arial,sans-serif;
  font-size:14px; line-height:1.45;
  height:100dvh; overflow:hidden;
  -webkit-font-smoothing:antialiased;
}
button{font:inherit;color:inherit;background:none;border:0;cursor:pointer}
/* .drop e .seg tem display proprio: sem isto o atributo hidden nao esconderia. */
[hidden]{display:none!important}
:focus-visible{outline:2px solid var(--accent);outline-offset:1px;border-radius:3px}

.app{height:100dvh;display:grid;grid-template-rows:auto 1fr auto}

/* ---------- barra superior ---------- */
.top{
  display:flex;align-items:center;gap:14px;
  padding:0 14px;height:52px;
  background:var(--surface);border-bottom:1px solid var(--line);
}
.brand{display:flex;align-items:baseline;gap:9px;flex:none}
.brand b{
  font-family:"Familjen Grotesk","Archivo",sans-serif;font-weight:700;
  font-size:18px;letter-spacing:-.02em;
}
.brand b i{font-style:normal;color:var(--accent)}
.brand span{font-size:11px;color:var(--ink-3);letter-spacing:.08em;text-transform:uppercase}
.searchwrap{flex:1;max-width:520px;position:relative;display:flex;align-items:center}
.searchwrap svg{position:absolute;left:9px;width:14px;height:14px;color:var(--ink-3);pointer-events:none}
#q{
  width:100%;min-width:0;padding:7px 10px 7px 29px;border-radius:7px;
  border:1px solid var(--line);background:var(--surface-2);color:var(--ink);font:inherit;
}
#q::placeholder{color:var(--ink-3)}
.kbd{
  position:absolute;right:8px;font-family:"JetBrains Mono",monospace;font-size:10px;
  color:var(--ink-3);border:1px solid var(--line);border-radius:4px;padding:1px 5px;
  background:var(--surface);pointer-events:none;
}
.top-right{margin-left:auto;display:flex;align-items:center;gap:8px;flex:none}
.chip{
  display:inline-flex;align-items:center;gap:5px;font-size:11px;
  padding:3px 8px;border-radius:20px;border:1px solid var(--line);
  color:var(--ink-2);background:var(--surface-2);white-space:nowrap;
}
.chip.ro{color:var(--accent-ink);border-color:var(--accent);background:var(--accent-wash)}
.chip.act{cursor:pointer}
.chip.act:hover{border-color:var(--ink-3)}
.chip.act svg{width:13px;height:13px;flex:none}
#btn-tema{padding:4px 7px}
.dot{width:6px;height:6px;border-radius:50%;background:var(--ok);flex:none}
.dot.off{background:var(--crit)}

/* ---------- paineis ---------- */
.panes{display:grid;grid-template-columns:272px 300px 1fr;min-height:0}
.pane{min-height:0;min-width:0;display:flex;flex-direction:column;border-right:1px solid var(--line);background:var(--surface)}
.pane:last-child{border-right:0;background:var(--ground)}
.pane-head{
  flex:none;display:flex;align-items:center;gap:8px;
  padding:9px 12px;border-bottom:1px solid var(--line-soft);
  font-size:10.5px;letter-spacing:.1em;text-transform:uppercase;color:var(--ink-3);font-weight:600;
}
.pane-head .count{
  margin-left:auto;font-family:"JetBrains Mono",monospace;letter-spacing:0;
  font-size:11px;color:var(--ink-3);
}
.scroll{overflow:auto;min-height:0;flex:1;scrollbar-width:thin}

/* ---------- painel do jar ---------- */
.jarpane{padding:12px}
.drop{
  display:grid;place-items:center;gap:6px;text-align:center;
  padding:26px 14px;border:1.5px dashed var(--line);border-radius:10px;
  background:var(--surface-2);color:var(--ink-3);cursor:pointer;transition:border-color .12s,background .12s;
}
.drop:hover,.drop.over{border-color:var(--accent);background:var(--accent-wash);color:var(--ink-2)}
.drop svg{width:26px;height:26px;color:var(--ink-3)}
.drop.over svg{color:var(--accent)}
.drop b{font-size:13px;color:var(--ink)}
.drop span{font-size:11.5px}
.drop small{font-size:10.5px;line-height:1.5;color:var(--ink-3);max-width:210px}
.lnk{color:var(--accent-ink);text-decoration:underline;cursor:pointer}

/* ---------- origem do jar: base x upload ---------- */
.seg{
  display:flex;gap:4px;padding:3px;margin-bottom:10px;
  border:1px solid var(--line);border-radius:9px;background:var(--surface-2);
}
.segb{flex:1;font-size:11.5px;padding:5px 6px;border-radius:6px;color:var(--ink-3)}
.segb.on{background:var(--surface);color:var(--ink);box-shadow:var(--shadow)}
.segb:disabled{opacity:.45;cursor:not-allowed}

.minisearch{position:relative;display:flex;align-items:center;margin-bottom:8px}
.minisearch input{
  width:100%;min-width:0;padding:6px 9px;border-radius:7px;font:inherit;font-size:12px;
  border:1px solid var(--line);background:var(--surface-2);color:var(--ink);
}
.minisearch input::placeholder{color:var(--ink-3)}

.modlist{display:grid;gap:5px}
.modrow{
  display:block;width:100%;text-align:left;padding:7px 9px;
  border:1px solid var(--line);border-radius:9px;background:var(--ground);
}
.modrow:hover{border-color:var(--ink-3)}
.modrow.on{border-color:var(--accent)}
.modrow .dsc{font-size:12px;color:var(--ink);line-height:1.35;word-break:break-word}
.modrow .pkg{
  font-family:"JetBrains Mono",monospace;font-size:10.5px;color:var(--ink-3);word-break:break-all;
}
.modrow .qt{
  float:right;margin-left:6px;padding:0 5px;font-family:"JetBrains Mono",monospace;font-size:10px;
  color:var(--ink-3);border:1px solid var(--line);border-radius:20px;
}
.jarlist{display:grid;gap:4px;margin:5px 0 2px 8px;padding-left:8px;border-left:1px solid var(--line)}
.jarrow{
  display:flex;align-items:center;gap:6px;width:100%;text-align:left;padding:5px 8px;
  border:1px solid var(--line-soft);border-radius:7px;background:var(--surface);
  font-family:"JetBrains Mono",monospace;font-size:11px;color:var(--ink-2);
}
.jarrow:hover{border-color:var(--ink-3);color:var(--ink)}
.jarrow.on{border-color:var(--accent);background:var(--accent-wash);color:var(--accent-ink)}
.jarrow .nm{overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.jarrow .tam{margin-left:auto;flex:none;font-size:10px;color:var(--ink-3)}
.jarlist .empty,.modlist .empty{padding:7px 2px;text-align:left;font-size:11.5px}
.permaviso{
  display:flex;align-items:flex-start;gap:6px;margin:0 0 10px;padding:7px 9px;
  border:1px solid var(--line);border-radius:9px;background:var(--surface-2);
  font-size:11.5px;line-height:1.45;color:var(--ink-2);
}
.permaviso b{flex:none;color:var(--accent-ink);font-weight:600}
.jarcard .orig{margin-top:4px;font-size:11px;line-height:1.4;color:var(--ink-3)}

.jarcard{
  margin-top:12px;border:1px solid var(--line);border-radius:10px;background:var(--ground);
  padding:11px 12px;
}
.jarcard .nm{
  font-family:"JetBrains Mono",monospace;font-size:12.5px;color:var(--ink);
  word-break:break-all;line-height:1.4;
}
.jarcard dl{display:grid;grid-template-columns:auto 1fr;gap:3px 10px;margin:9px 0 0;font-size:11.5px}
.jarcard dt{color:var(--ink-3)}
.jarcard dd{margin:0;color:var(--ink-2);font-family:"JetBrains Mono",monospace;text-align:right}
.jarcard .acoes{display:flex;flex-wrap:wrap;gap:7px;margin-top:11px}

.prog{margin-top:12px}
.prog .bar{height:5px;border-radius:3px;background:var(--surface-2);overflow:hidden}
.prog .bar i{display:block;height:100%;width:0;background:var(--accent);transition:width .15s}
.prog span{display:block;margin-top:6px;font-size:11px;color:var(--ink-3);font-family:"JetBrains Mono",monospace}

.aviso{
  margin-top:12px;border:1px solid var(--crit);border-radius:9px;background:var(--crit-wash);
  padding:10px 11px;font-size:11.5px;line-height:1.55;color:var(--ink-2);
}
.aviso b{display:block;color:var(--crit);font-size:11px;letter-spacing:.05em;text-transform:uppercase;margin-bottom:4px}
.aviso code{font-family:"JetBrains Mono",monospace;font-size:11px;color:var(--accent-ink);word-break:break-all}

.legenda{margin-top:14px;display:grid;gap:5px;font-size:10.5px;color:var(--ink-3)}
.legenda div{display:flex;align-items:center;gap:7px}
.legenda em{font-style:normal;font-family:"Archivo",sans-serif;font-size:9px;font-weight:700;
  letter-spacing:.06em;text-transform:uppercase;flex:none;width:26px}
.legenda em.src{color:var(--ok)}
.legenda em.dec{color:var(--accent)}
.legenda em.arq{color:var(--info)}

/* ---------- arvore ---------- */
.tree{padding:6px 0 24px}
.node{
  display:flex;align-items:center;gap:6px;width:100%;text-align:left;
  padding:3px 10px 3px 0;font-size:13px;line-height:1.5;color:var(--ink-2);
  font-family:"JetBrains Mono",monospace;
}
.node:hover{background:var(--surface-2)}
.node[aria-current="true"]{background:var(--sel);color:var(--ink)}
.node .tw{width:12px;flex:none;color:var(--ink-2);font-size:11px;line-height:1;text-align:center;transition:transform .12s}
.node.collapsed .tw{transform:rotate(-90deg)}
.node .ic{width:14px;flex:none;display:grid;place-items:center;color:var(--ink-3)}
.node .nm{overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.node.pkg .nm{color:var(--ink-2)}
.node.cls .nm{color:var(--ink)}
.node .tag{
  margin-left:auto;font-family:"Archivo",sans-serif;font-size:9px;font-weight:600;
  letter-spacing:.06em;text-transform:uppercase;color:var(--ink-3);flex:none;
}
.node .tag.src{color:var(--ok)}
.node .tag.dec{color:var(--accent)}
.node .tag.arq{color:var(--info)}
.empty{padding:28px 16px;color:var(--ink-3);font-size:12.5px;text-align:center;line-height:1.6}
.empty b{color:var(--ink-2)}

/* ---------- visualizador ---------- */
.tabs{
  flex:none;display:flex;align-items:stretch;overflow-x:auto;
  background:var(--surface);border-bottom:1px solid var(--line);height:37px;
  scrollbar-width:none;min-width:0;
}
.tabs::-webkit-scrollbar{display:none}
.tab{
  display:flex;align-items:center;gap:7px;padding:0 10px 0 12px;white-space:nowrap;
  border-right:1px solid var(--line-soft);font-size:12.5px;color:var(--ink-3);
  font-family:"JetBrains Mono",monospace;
}
.tab:hover{color:var(--ink-2)}
.tab[aria-current="true"]{color:var(--ink);background:var(--ground);box-shadow:inset 0 -2px 0 var(--accent)}
.tab .x{width:15px;height:15px;border-radius:3px;display:grid;place-items:center;font-size:13px;line-height:1;color:var(--ink-3)}
.tab .x:hover{background:var(--line);color:var(--ink)}

.filehead{
  flex:none;display:flex;align-items:center;gap:10px;flex-wrap:wrap;
  padding:9px 14px;border-bottom:1px solid var(--line-soft);background:var(--ground);
}
.filehead .fqn{font-family:"JetBrains Mono",monospace;font-size:12.5px;color:var(--ink-2);word-break:break-all}
.filehead .fqn b{color:var(--ink);font-weight:700}
.filehead .right{margin-left:auto;display:flex;gap:7px;align-items:center}
.btn{
  font-size:11.5px;padding:4px 9px;border-radius:6px;border:1px solid var(--line);
  color:var(--ink-2);background:var(--surface);
}
.btn:hover{border-color:var(--ink-3);color:var(--ink)}
.btn.danger:hover{border-color:var(--crit);color:var(--crit)}

.code{flex:1;min-height:0;min-width:0;overflow:auto;background:var(--ground)}
.code table{border-collapse:collapse;width:100%}
.code td{vertical-align:top;padding:0}
.code td.ln{
  width:1%;text-align:right;padding:0 12px 0 14px;user-select:none;
  color:var(--gutter);font-family:"JetBrains Mono",monospace;font-size:12.5px;line-height:1.65;
  font-variant-numeric:tabular-nums;position:sticky;left:0;background:var(--ground);
  border-right:1px solid var(--line-soft);
}
.code pre{
  margin:0;padding:0 20px 40px 12px;font-family:"JetBrains Mono",monospace;
  font-size:12.5px;line-height:1.65;color:var(--ink);white-space:pre;
}
.code .c{color:var(--c-comment);font-style:italic}
.code .s{color:var(--c-string)}
.code .k{color:var(--c-key);font-weight:500}
.code .a{color:var(--c-anno)}
.code .n{color:var(--c-num)}
.code .t{color:var(--c-type)}
.code .f{color:var(--c-fn)}
.code i{font-style:normal}
.code .c i{font-style:italic}

.loading{display:flex;align-items:center;gap:9px;padding:24px 18px;color:var(--ink-3);font-size:12.5px}
.spin{
  width:13px;height:13px;flex:none;border-radius:50%;
  border:2px solid var(--line);border-top-color:var(--accent);animation:gira .7s linear infinite;
}
@keyframes gira{to{transform:rotate(360deg)}}

/* ---------- resultados de busca ---------- */
.results{padding:6px 0 24px}
.res{display:block;width:100%;text-align:left;padding:7px 12px;border-bottom:1px solid var(--line-soft)}
.res:hover{background:var(--surface-2)}
.res .t1{font-family:"JetBrains Mono",monospace;font-size:12.5px;color:var(--ink)}
.res .t2{font-size:11px;color:var(--ink-3);font-family:"JetBrains Mono",monospace;margin-top:2px;
  overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
mark{background:var(--accent-wash);color:var(--accent-ink);border-radius:2px;padding:0 1px}

/* ---------- barra de status ---------- */
.status{
  flex:none;height:26px;display:flex;align-items:center;gap:14px;padding:0 14px;
  background:var(--surface);border-top:1px solid var(--line);
  font-size:11px;color:var(--ink-3);font-family:"JetBrains Mono",monospace;overflow:hidden;
}
.status span{white-space:nowrap;overflow:hidden;text-overflow:ellipsis;min-width:0}
.status .sep{color:var(--line);flex:none}
.status .right{margin-left:auto;display:flex;gap:14px;flex:none;overflow:visible}

/* ---------- modal ---------- */
.overlay{position:fixed;inset:0;background:var(--veil);display:grid;place-items:center;padding:24px;z-index:50}
.overlay[hidden]{display:none}
.modal{
  background:var(--surface);border:1px solid var(--line);border-radius:12px;
  box-shadow:var(--shadow);max-width:680px;width:100%;max-height:82dvh;overflow:auto;
}
.modal-head{
  display:flex;align-items:center;gap:10px;padding:16px 20px 12px;
  border-bottom:1px solid var(--line-soft);position:sticky;top:0;background:var(--surface);
}
.modal-head h2{margin:0;font-family:"Familjen Grotesk",sans-serif;font-size:17px;font-weight:600;letter-spacing:-.01em}
.modal-head .btn{margin-left:auto}
.modal-body{padding:16px 20px 22px;color:var(--ink-2);font-size:13px;line-height:1.6}
.modal-body h3{
  font-family:"Familjen Grotesk",sans-serif;font-size:12px;font-weight:600;color:var(--ink);
  text-transform:uppercase;letter-spacing:.08em;margin:20px 0 8px;
}
.modal-body h3:first-child{margin-top:0}
.modal-body p{margin:0 0 10px}
.modal-body ol,.modal-body ul{margin:0 0 10px;padding-left:18px}
.modal-body li{margin-bottom:5px}
.modal-body pre{
  background:var(--ground);border:1px solid var(--line-soft);border-radius:8px;
  padding:12px 14px;overflow-x:auto;font-family:"JetBrains Mono",monospace;font-size:11.5px;
  line-height:1.6;color:var(--ink);margin:0 0 10px;white-space:pre-wrap;word-break:break-all;
}
.modal-body code{font-family:"JetBrains Mono",monospace;font-size:12px;color:var(--accent-ink)}

/* ---------- analise do jar ---------- */
.modal.largo{max-width:960px}
.modal-head .seg{margin:0;flex:none}
.modal-head .segb{flex:none;padding:5px 12px}
.pills{display:flex;flex-wrap:wrap;gap:6px;margin:0 0 10px}
.pill{
  display:inline-flex;align-items:center;gap:5px;flex:none;padding:2px 8px;border-radius:999px;
  border:1px solid var(--line);background:var(--surface-2);font-size:11.5px;color:var(--ink-2);white-space:nowrap;
}
.pill b{color:var(--ink)}
.pill.forte{border-color:var(--accent);background:var(--accent-wash);color:var(--accent-ink)}
.tabwrap{overflow-x:auto;margin:0 0 10px}
.tab-analise{width:100%;border-collapse:collapse;font-size:12px}
.tab-analise th,.tab-analise td{text-align:left;padding:5px 8px;border-bottom:1px solid var(--line-soft)}
.tab-analise th{color:var(--ink-3);font-weight:500}
.tab-analise td+td,.tab-analise th+th{text-align:right;font-family:"JetBrains Mono",monospace}
.pkg-analise{border:1px solid var(--line);border-radius:9px;margin-bottom:8px;background:var(--surface-2)}
.pkg-analise > summary{display:flex;align-items:center;gap:8px;padding:8px 12px;cursor:pointer;min-width:0}
.pkg-analise > summary code{flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;color:var(--ink)}
.pkg-analise[open] > summary{border-bottom:1px solid var(--line-soft)}
.pkg-classes{padding:8px 8px 2px}
.cls-analise{border:1px solid var(--line-soft);border-radius:8px;margin-bottom:6px;background:var(--ground)}
.cls-analise summary{display:flex;align-items:center;gap:8px;padding:7px 10px;cursor:pointer;min-width:0}
.cls-analise summary code{overflow:hidden;text-overflow:ellipsis;white-space:nowrap;color:var(--ink-2)}
.cls-analise summary code b{color:var(--ink)}
.cls-analise[open] summary{border-bottom:1px solid var(--line-soft)}
.cls-analise > p{margin:10px 12px;color:var(--ink)}
.cls-analise .btn{margin:0 12px 12px}
.ficha{display:grid;grid-template-columns:auto 1fr;gap:4px 12px;margin:0 12px 12px;font-size:12px}
.ficha dt{color:var(--ink-3)}
.ficha dd{margin:0;color:var(--ink);word-break:break-word;font-family:"JetBrains Mono",monospace;font-size:11.5px}
.mais{color:var(--ink-3)}

/* ---------- responsivo ---------- */
.back{display:none}
@media (max-width:1080px){ .panes{grid-template-columns:240px 250px 1fr} }
@media (max-width:900px){
  .panes{grid-template-columns:1fr}
  .pane{border-right:0}
  .top{flex-wrap:wrap;height:auto;padding:8px 12px;gap:8px}
  .searchwrap{order:3;flex:1 1 100%;max-width:none}
  .chip.ro{display:none}
  .status .right{display:none}
  .app[data-view="jar"] .pane:not(.p-jar){display:none}
  .app[data-view="tree"] .pane:not(.p-tree){display:none}
  .app[data-view="code"] .pane:not(.p-code){display:none}
  .modal-head{flex-wrap:wrap}
  .ficha{grid-template-columns:1fr}
  .back{display:inline-flex;align-items:center;gap:5px}
  .brand span{display:none}
  .kbd{display:none}
}
@media (prefers-reduced-motion:reduce){*{transition:none!important;animation:none!important}}
</style>
<script>
/* Aplica o tema salvo antes do primeiro paint para nao piscar a cor errada.
   O gadget roda em iframe do OM: storage pode lancar em contexto restrito. */
(function () {
  try {
    var salvo = window.localStorage.getItem('jvexplorer.tema');
    if (salvo === 'light') document.documentElement.setAttribute('data-theme', 'light');
  } catch (e) { /* storage indisponivel: mantem o tema escuro */ }
})();
</script>
</head>
<body>

<div class="app" id="app" data-view="jar">

  <header class="top">
    <div class="brand"><b>JV<i>Explorer</i></b><span>Sankhya&nbsp;Om</span></div>
    <div class="searchwrap">
      <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.6"><circle cx="7" cy="7" r="4.5"/><path d="M10.5 10.5 14 14"/></svg>
      <input id="q" type="search" placeholder="Buscar classe, pacote ou trecho de codigo..." autocomplete="off" spellcheck="false" disabled>
      <span class="kbd">Ctrl K</span>
    </div>
    <div class="top-right">
      <span class="chip ro" title="O JVExplorer nunca grava no banco: o JAR vive so na sua sessao">Somente leitura</span>
      <button class="chip act" id="btn-info"><span class="dot" id="dot-cfr"></span>Diagnostico</button>
      <button class="chip act" id="btn-tema" type="button" aria-pressed="false">
        <svg id="ico-tema" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" aria-hidden="true"></svg>
      </button>
    </div>
  </header>

  <div class="panes">

    <section class="pane p-jar">
      <div class="pane-head">Arquivo <span class="count" id="jar-count"></span></div>
      <div class="scroll">
        <div class="jarpane">
          <div class="seg" id="seg">
            <button class="segb on" type="button" data-origem="base" id="seg-base">Modulos da base</button>
            <button class="segb" type="button" data-origem="upload" id="seg-upload">Upload</button>
          </div>

          <p class="permaviso" id="perm-aviso" hidden></p>

          <div id="origem-base">
            <div class="minisearch">
              <input id="q-mod" type="search" placeholder="Buscar modulo por nome ou pacote..."
                     autocomplete="off" spellcheck="false">
            </div>
            <div class="modlist" id="modlist"></div>
          </div>

          <div class="drop" id="drop" hidden>
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M12 16V4m0 0L8 8m4-4 4 4"/><path d="M4 15v3a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-3"/></svg>
            <b>Solte o .jar aqui</b>
            <span>ou <label class="lnk" for="file">selecione o arquivo</label></span>
            <input type="file" id="file" accept=".jar,.zip" hidden>
            <small>Descompilado em tempo de consulta. Nada e gravado em banco: ao fechar a sessao o processo recomeca.</small>
          </div>

          <div class="jarcard" id="jar-info" hidden></div>
          <div class="prog" id="prog" hidden><div class="bar"><i id="prog-bar"></i></div><span id="prog-txt"></span></div>
          <div class="aviso" id="aviso" hidden></div>

          <div class="legenda">
            <div><em class="src">src</em><span>fonte original embutido no JAR</span></div>
            <div><em class="dec">dec</em><span>reconstruido do bytecode pelo CFR</span></div>
            <div><em class="arq">arq</em><span>recurso do JAR (xml, sql, properties)</span></div>
          </div>
        </div>
      </div>
    </section>

    <section class="pane p-tree">
      <div class="pane-head">
        <button class="back btn" id="back-jar">&lsaquo; Arquivo</button>
        <span id="tree-title">Estrutura</span>
        <span class="count" id="tree-count"></span>
      </div>
      <div class="scroll"><div class="tree" id="tree"></div></div>
    </section>

    <section class="pane p-code">
      <div class="tabs" id="tabs"></div>
      <div class="filehead" id="filehead"></div>
      <div class="code" id="code"></div>
    </section>

  </div>

  <footer class="status">
    <span id="st-jar">nenhum jar carregado</span>
    <span class="sep">&#9474;</span>
    <span id="st-file">nenhum arquivo aberto</span>
    <span class="right">
      <span id="st-origem"></span>
      <span id="st-lines"></span>
    </span>
  </footer>
</div>

<div class="overlay" id="overlay" hidden>
  <div class="modal" id="modal" role="dialog" aria-modal="true" aria-labelledby="mtitle">
    <div class="modal-head">
      <h2 id="mtitle">Diagnostico</h2>
      <div class="seg" id="modal-abas"></div>
      <button class="btn" id="btn-close">Fechar</button>
    </div>
    <div class="modal-body" id="modal-body"></div>
  </div>
</div>
<script>
/* ============================================================
   JVExplorer - camada de apresentacao
   A mesma URL responde a interface e a API (?action=...).
   ============================================================ */

var API_BASES = ["<%= escapeJson(urlMge) %>", "<%= escapeJson(urlJsp) %>"];
/* Mesma frase do servidor: a regra de permissao vive no JSP, nao no cliente. */
var AVISO_SUP = "<%= escapeJson(AVISO_SUP) %>";
var CHUNK = 4 * 1024 * 1024;
var MAX_ABAS = 10;

var S = {
  jar: null,
  itens: [],
  indice: {},
  cache: {},
  abas: [],
  ativo: null,
  colapsados: {},
  busca: '',
  cfr: false,
  sup: false,
  origem: 'base',
  modulos: [],
  jars: {},
  modAberto: null,
  timerMod: null,
  analise: null
};

var $ = function (id) { return document.getElementById(id); };
var baseOk = null;

/* ---------------- helpers ---------------- */
var esc = function (s) {
  return String(s).replace(/[&<>]/g, function (c) {
    return c === '&' ? '&amp;' : (c === '<' ? '&lt;' : '&gt;');
  });
};

function nomeArq(path) { return path.substring(path.lastIndexOf('/') + 1); }

function ext(path) {
  var i = path.lastIndexOf('.');
  return i < 0 ? '' : path.substring(i + 1).toLowerCase();
}

function fmtBytes(n) {
  if (n === null || n === undefined) return '-';
  if (n < 1024) return n + ' B';
  if (n < 1048576) return (n / 1024).toFixed(1) + ' KB';
  return (n / 1048576).toFixed(1) + ' MB';
}

function isMobile() { return window.matchMedia('(max-width:900px)').matches; }
function setView(v) { if (isMobile()) $('app').dataset.view = v; }

/* ---------------- transporte ---------------- */
function montarUrl(base, acao, params) {
  var url = String(base).replace(/([?&])action=[^&]*/g, '$1').replace(/[?&]$/, '');
  url += (url.indexOf('?') >= 0 ? '&' : '?') + 'action=' + encodeURIComponent(acao);
  if (params) {
    for (var k in params) {
      if (Object.prototype.hasOwnProperty.call(params, k)) {
        url += '&' + encodeURIComponent(k) + '=' + encodeURIComponent(params[k]);
      }
    }
  }
  return url;
}

async function requisitar(base, acao, params, corpo) {
  var opcoes = { credentials: 'include', cache: 'no-store' };
  if (corpo !== undefined && corpo !== null) {
    opcoes.method = 'POST';
    opcoes.body = corpo;
    opcoes.headers = { 'Content-Type': 'application/octet-stream' };
  }
  var resp = await fetch(montarUrl(base, acao, params), opcoes);
  var texto = await resp.text();
  if (!resp.ok) throw new Error('HTTP ' + resp.status + (texto ? ' - ' + texto.substring(0, 160) : ''));
  var dados;
  try { dados = JSON.parse(texto); }
  catch (e) { throw new Error('Resposta nao-JSON do servidor.'); }
  if (!dados.success) throw new Error(dados.error || 'Falha na operacao.');
  return dados;
}

function rotasCandidatas() {
  if (!baseOk) return API_BASES;
  return [baseOk].concat(API_BASES.filter(function (b) { return b !== baseOk; }));
}

/* Duas rotas possiveis: html5component.mge e o caminho real do JSP.
   A primeira que responder JSON vira a rota da sessao. Usado somente em
   leituras idempotentes: o upload resolve a rota antes, via probe. */
async function chamar(acao, params, corpo) {
  var bases = rotasCandidatas();
  var ultimo = null;
  for (var i = 0; i < bases.length; i++) {
    try {
      var dados = await requisitar(bases[i], acao, params, corpo);
      baseOk = bases[i];
      return dados;
    } catch (e) { ultimo = e; }
  }
  throw ultimo || new Error('Sem resposta do servidor.');
}

/* Fixa a rota que aceita POST antes de enviar blocos: um retry de bloco em
   outra rota duplicaria bytes no arquivo temporario. */
async function resolverRotaPost() {
  var bases = rotasCandidatas();
  var ultimo = null;
  for (var i = 0; i < bases.length; i++) {
    try {
      await requisitar(bases[i], 'probe', null, new Blob([]));
      baseOk = bases[i];
      return;
    } catch (e) { ultimo = e; }
  }
  throw ultimo || new Error('Nenhuma rota aceita POST neste ambiente.');
}

/* ---------------- realce de sintaxe ---------------- */
var RE_JAVA = new RegExp([
  '(\\/\\*[\\s\\S]*?\\*\\/|\\/\\/[^\\n]*)',
  '("(?:\\\\.|[^"\\\\])*"|\'(?:\\\\.|[^\'\\\\])*\')',
  '(@\\w+)',
  '\\b(abstract|assert|boolean|break|byte|case|catch|char|class|const|continue|default|do|double|else|enum|extends|final|finally|float|for|goto|if|implements|import|instanceof|int|interface|long|native|new|package|private|protected|public|return|short|static|strictfp|super|switch|synchronized|this|throw|throws|transient|try|void|volatile|while|var|record|true|false|null)\\b',
  '\\b(\\d[\\d_]*\\.?\\d*[fFdDlL]?)\\b',
  '\\b([A-Z][A-Za-z0-9_]*)\\b',
  '\\b([a-z_]\\w*)(?=\\s*\\()'
].join('|'), 'g');

var RE_XML = /(<!--[\s\S]*?-->)|("[^"]*")|(<\/?[\w:.-]+)|(\/?>)|([\w:.-]+)(?==)/g;
var RE_PROP = /(^#[^\n]*)|(^[\w.-]+)(?=[:=])|([:=])/gm;
var RE_SQL = new RegExp([
  '(--[^\\n]*|\\/\\*[\\s\\S]*?\\*\\/)',
  '(\'(?:\'\'|[^\'])*\')',
  '\\b(SELECT|FROM|WHERE|JOIN|LEFT|RIGHT|INNER|OUTER|ON|AND|OR|NOT|IN|EXISTS|GROUP|ORDER|BY|HAVING|UNION|ALL|INSERT|INTO|VALUES|UPDATE|SET|DELETE|CREATE|TABLE|VIEW|INDEX|ALTER|DROP|AS|CASE|WHEN|THEN|ELSE|END|NULL|IS|DISTINCT|COUNT|SUM|MAX|MIN|AVG|COALESCE|NVL|TRUNC|TO_DATE|TO_CHAR)\\b',
  '\\b(\\d+(?:\\.\\d+)?)\\b'
].join('|'), 'gi');

function tokenizar(src, re, classes) {
  var saida = '', ultimo = 0, m;
  re.lastIndex = 0;
  while ((m = re.exec(src)) !== null) {
    if (m[0] === '') { re.lastIndex++; continue; }
    saida += esc(src.slice(ultimo, m.index));
    var cls = null;
    for (var i = 1; i < m.length; i++) {
      if (m[i] !== undefined) { cls = classes[i - 1]; break; }
    }
    saida += cls ? '<i class="' + cls + '">' + esc(m[0]) + '</i>' : esc(m[0]);
    ultimo = m.index + m[0].length;
  }
  return saida + esc(src.slice(ultimo));
}

function realce(src, e) {
  if (e === 'java' || e === 'kt') return tokenizar(src, RE_JAVA, ['c', 's', 'a', 'k', 'n', 't', 'f']);
  if (e === 'xml' || e === 'xsd' || e === 'tld' || e === 'dtd' || e === 'html' || e === 'htm' || e === 'jsp') {
    return tokenizar(src, RE_XML, ['c', 's', 't', 't', 'a']);
  }
  if (e === 'sql') return tokenizar(src, RE_SQL, ['c', 's', 'k', 'n']);
  if (e === 'properties' || e === 'mf' || e === 'ini' || e === 'cfg') return tokenizar(src, RE_PROP, ['c', 't', 'k']);
  return esc(src);
}

/* ---------------- upload ---------------- */
function mostrarProgresso(pct, rotulo) {
  $('prog').hidden = false;
  $('prog-bar').style.width = pct + '%';
  $('prog-txt').textContent = rotulo;
}

function esconderProgresso() { $('prog').hidden = true; }

function mostrarAviso(html) {
  $('aviso').hidden = false;
  $('aviso').innerHTML = html;
}

function erro(msg) {
  mostrarAviso('<b>Falha</b>' + esc(msg));
}

/* Reexibido apos cada upload: o aviso do CFR e permanente enquanto o jar nao for achado. */
function avisoCfr() {
  if (S.cfr) { $('aviso').hidden = true; return; }
  mostrarAviso('<b>Descompilador ausente</b>Nenhum <code>cfr*.jar</code> foi encontrado no servidor. ' +
    'Fontes e recursos embutidos no jar continuam abrindo; classes sem fonte nao. ' +
    'Veja <b>Diagnostico</b>.');
}

/* ---------------- modulos java da base ---------------- */
function trocarOrigem(origem) {
  if (origem === 'base' && !S.sup) return;
  S.origem = origem;
  $('seg-base').classList.toggle('on', origem === 'base');
  $('seg-upload').classList.toggle('on', origem === 'upload');
  $('origem-base').hidden = origem !== 'base';
  $('drop').hidden = origem !== 'upload';
  sincronizarCardJar();
}

/* O card pertence a aba de onde o jar veio: na outra aba ele nao aparece. */
function sincronizarCardJar() {
  var visivel = Boolean(S.jar) && (S.jar.codModulo ? 'base' : 'upload') === S.origem;
  $('jar-info').hidden = !visivel;
  $('jar-count').textContent = visivel ? S.jar.classes : '';
}

function agendarBuscaModulos() {
  clearTimeout(S.timerMod);
  S.timerMod = setTimeout(buscarModulos, 300);
}

async function buscarModulos() {
  $('modlist').innerHTML = '<div class="empty">buscando modulos...</div>';
  try {
    var dados = await chamar('modulos', { q: $('q-mod').value.trim() });
    S.modulos = dados.modulos;
    renderModulos();
  } catch (e) {
    $('modlist').innerHTML = '<div class="empty">' + esc(e.message) + '</div>';
  }
}

function htmlJars(codModulo) {
  var jars = S.jars[codModulo];
  if (!jars) return '<div class="empty">carregando jars...</div>';
  if (!jars.length) return '<div class="empty">Modulo sem jar cadastrado.</div>';
  var html = '';
  for (var i = 0; i < jars.length; i++) {
    var ativo = S.jar && S.jar.codModulo === codModulo && S.jar.codJar === jars[i].cod;
    html += '<button class="jarrow' + (ativo ? ' on' : '') + '" type="button" data-mod="' + codModulo +
      '" data-jar="' + jars[i].cod + '" title="' + esc(jars[i].descricao) + '">' +
      '<span class="nm">' + esc(jars[i].descricao) + '</span>' +
      '<span class="tam">' + fmtBytes(jars[i].tamanho) + '</span></button>';
  }
  return html;
}

function htmlModulo(mod) {
  var aberto = S.modAberto === mod.cod;
  return '<div>' +
    '<button class="modrow' + (aberto ? ' on' : '') + '" type="button" data-mod="' + mod.cod + '">' +
      '<span class="qt">' + mod.jars + (mod.jars === 1 ? ' jar' : ' jars') + '</span>' +
      '<span class="dsc">' + esc(mod.descr) + '</span>' +
      '<span class="pkg">' + esc(mod.pacote) + '</span>' +
    '</button>' +
    (aberto ? '<div class="jarlist">' + htmlJars(mod.cod) + '</div>' : '') +
  '</div>';
}

function renderModulos() {
  if (!S.modulos.length) {
    $('modlist').innerHTML = '<div class="empty">Nenhum modulo java encontrado.</div>';
    return;
  }
  var html = '';
  for (var i = 0; i < S.modulos.length; i++) html += htmlModulo(S.modulos[i]);
  $('modlist').innerHTML = html;
  ligarModulos();
}

function ligarModulos() {
  var mods = $('modlist').querySelectorAll('.modrow');
  for (var i = 0; i < mods.length; i++) {
    mods[i].onclick = function () { alternarModulo(Number(this.dataset.mod)); };
  }
  var jars = $('modlist').querySelectorAll('.jarrow');
  for (var j = 0; j < jars.length; j++) {
    jars[j].onclick = function () {
      abrirDaBase(Number(this.dataset.mod), Number(this.dataset.jar));
    };
  }
}

async function alternarModulo(codModulo) {
  S.modAberto = S.modAberto === codModulo ? null : codModulo;
  renderModulos();
  if (S.modAberto === null || S.jars[codModulo]) return;
  try {
    var dados = await chamar('jars', { mod: codModulo });
    S.jars[codModulo] = dados.jars;
  } catch (e) {
    S.jars[codModulo] = [];
    erro(e.message);
  }
  renderModulos();
}

/* Um jar ativo por sessao: trocar de jar recarrega o BLOB e reindexa. */
async function abrirDaBase(codModulo, codJar) {
  $('aviso').hidden = true;
  mostrarProgresso(45, 'carregando jar da base...');
  try {
    var resposta = await chamar('abrir', { mod: codModulo, jar: codJar });
    mostrarProgresso(100, 'indexando...');
    esconderProgresso();
    aplicarJar(resposta);
    renderModulos();
    avisoCfr();
  } catch (e) {
    esconderProgresso();
    erro(e.message);
  }
}

async function enviarJar(arquivo) {
  if (!/\.(jar|zip)$/i.test(arquivo.name)) { erro('Selecione um arquivo .jar.'); return; }
  $('aviso').hidden = true;
  var partes = Math.max(1, Math.ceil(arquivo.size / CHUNK));
  var resposta = null;
  try {
    mostrarProgresso(0, 'preparando envio...');
    await resolverRotaPost();
    for (var i = 0; i < partes; i++) {
      var ultima = i === partes - 1;
      var fatia = arquivo.slice(i * CHUNK, Math.min(arquivo.size, (i + 1) * CHUNK));
      mostrarProgresso(Math.round((i / partes) * 100), 'enviando ' + fmtBytes(arquivo.size) + '...');
      resposta = await requisitar(baseOk, 'upload',
        { nome: arquivo.name, chunk: i, final: ultima ? 1 : 0 }, fatia);
      if (ultima) mostrarProgresso(100, 'indexando...');
    }
  } catch (e) {
    esconderProgresso();
    erro(e.message);
    return;
  }
  esconderProgresso();
  aplicarJar(resposta);
  avisoCfr();
}

function aplicarJar(resposta) {
  S.jar = resposta.jar;
  S.analise = null;
  S.itens = resposta.itens;
  S.indice = {};
  S.cache = {};
  S.abas = [];
  S.ativo = null;
  S.colapsados = {};
  S.busca = '';
  for (var i = 0; i < S.itens.length; i++) S.indice[S.itens[i].path] = S.itens[i];
  $('q').value = '';
  $('q').disabled = false;
  renderJarInfo();
  renderArvore();
  limparCodigo();
  $('st-jar').textContent = S.jar.nome + '  -  ' + S.jar.classes + ' classes';
  setView('tree');
}

async function resetar() {
  try { await chamar('reset'); } catch (e) { /* sessao ja limpa */ }
  S.jar = null; S.analise = null; S.itens = []; S.indice = {}; S.cache = {};
  S.abas = []; S.ativo = null; S.busca = '';
  $('q').value = ''; $('q').disabled = true;
  $('jar-info').hidden = true;
  $('jar-count').textContent = '';
  $('tree').innerHTML = '<div class="empty">Carregue um <b>.jar</b> para navegar nos pacotes.</div>';
  $('tree-count').textContent = '';
  $('st-jar').textContent = 'nenhum jar carregado';
  limparCodigo();
  if (S.modulos.length) renderModulos();
  setView('jar');
}

function renderJarInfo() {
  sincronizarCardJar();
  $('jar-info').innerHTML =
    '<div class="nm">' + esc(S.jar.nome) + '</div>' +
    (S.jar.rotulo ? '<div class="orig">' + esc(S.jar.rotulo) + '</div>' : '') +
    '<dl>' +
      '<dt>Tamanho</dt><dd>' + fmtBytes(S.jar.tamanho) + '</dd>' +
      '<dt>Entradas</dt><dd>' + S.jar.entradas + '</dd>' +
      '<dt>Classes</dt><dd>' + S.jar.classes + '</dd>' +
      '<dt>Navegaveis</dt><dd>' + S.jar.itens + '</dd>' +
    '</dl>' +
    htmlAcoesJar(Boolean(S.jar.codModulo));
  if ($('btn-trocar')) $('btn-trocar').onclick = trocarJar;
  if ($('btn-baixar')) $('btn-baixar').onclick = baixarJar;
  $('btn-reset').onclick = resetar;
}

/* Baixar so faz sentido para o jar da base: o de upload o usuario ja tem localmente. */
function htmlAcoesJar(daBase) {
  if (daBase) {
    return '<div class="acoes">' +
      '<button class="btn" id="btn-baixar">Baixar jar</button>' +
      '<button class="btn" id="btn-reset">Fechar</button>' +
    '</div>';
  }
  return '<div class="acoes">' +
    '<button class="btn" id="btn-trocar">Trocar jar</button>' +
    '<button class="btn danger" id="btn-reset">Descartar</button>' +
  '</div>';
}

/* Link nativo: o navegador baixa em stream, sem carregar o jar na memoria do JS. */
function baixarJar() {
  var link = document.createElement('a');
  link.href = montarUrl(baseOk || API_BASES[0], 'download');
  link.download = S.jar.nome;
  document.body.appendChild(link);
  link.click();
  link.remove();
}

/* So existe no card de upload: reabre o seletor de arquivo. */
function trocarJar() {
  trocarOrigem('upload');
  $('file').click();
}

/* ---------------- arvore ---------------- */
function montarArvore(itens) {
  var raiz = { nome: '', filhos: {}, ordem: [], item: null };
  for (var i = 0; i < itens.length; i++) {
    var no = raiz;
    var partes = itens[i].path.split('/');
    for (var p = 0; p < partes.length; p++) {
      var chave = partes[p];
      if (!no.filhos[chave]) {
        no.filhos[chave] = { nome: chave, filhos: {}, ordem: [], item: null };
        no.ordem.push(chave);
      }
      no = no.filhos[chave];
      if (p === partes.length - 1) no.item = itens[i];
    }
  }
  return comprimir(raiz);
}

/* pacotes de no unico viram uma linha so: br.com.dstech.financeiro */
function comprimir(no) {
  for (var i = 0; i < no.ordem.length; i++) {
    var chave = no.ordem[i];
    var filho = no.filhos[chave];
    comprimir(filho);
    if (filho.item || filho.ordem.length !== 1) continue;
    var netoChave = filho.ordem[0];
    var neto = filho.filhos[netoChave];
    if (neto.item) continue;
    neto.nome = filho.nome + '.' + neto.nome;
    delete no.filhos[chave];
    no.filhos[neto.nome] = neto;
    no.ordem[i] = neto.nome;
    i--;
  }
  return no;
}

var TAG = { src: 'src', dec: 'dec', arq: 'arq' };

var iconePasta = '<svg width="12" height="12" viewBox="0 0 16 16" fill="currentColor"><path d="M1.5 3.5h4l1.2 1.6h7.8v7.4H1.5z" opacity=".55"/></svg>';
var iconeClasse = '<svg width="12" height="12" viewBox="0 0 16 16" fill="currentColor"><path d="M4 2h5l3 3v9H4z" opacity=".35"/><path d="M6 8h4v1H6zm0 2h4v1H6z"/></svg>';
var iconeArquivo = '<svg width="12" height="12" viewBox="0 0 16 16" fill="currentColor" opacity=".5"><path d="M4 2h5l3 3v9H4z"/></svg>';

function linhaItem(item, nivel) {
  var atual = item.path === S.ativo ? 'true' : 'false';
  return '<button class="node cls" data-path="' + esc(item.path) + '" aria-current="' + atual + '"' +
    ' style="padding-left:' + (8 + nivel * 13) + 'px" title="' + esc(item.path) + '">' +
    '<span class="tw"></span><span class="ic">' + (item.tipo === 'class' ? iconeClasse : iconeArquivo) + '</span>' +
    '<span class="nm">' + esc(nomeArq(item.path)) + '</span>' +
    '<span class="tag ' + item.origem + '">' + TAG[item.origem] + '</span></button>';
}

function linhaPacote(no, nivel, id) {
  var fechado = S.colapsados[id] ? ' collapsed' : '';
  return '<button class="node pkg' + fechado + '" data-pkg="' + esc(id) + '"' +
    ' style="padding-left:' + (8 + nivel * 13) + 'px">' +
    '<span class="tw">&#9662;</span><span class="ic">' + iconePasta + '</span>' +
    '<span class="nm">' + esc(no.nome) + '</span></button>';
}

function ordenar(no) {
  var chaves = no.ordem.slice();
  chaves.sort(function (a, b) {
    var ia = no.filhos[a].item ? 1 : 0;
    var ib = no.filhos[b].item ? 1 : 0;
    return ia !== ib ? ia - ib : a.localeCompare(b);
  });
  return chaves;
}

function caminhar(no, nivel, prefixo, linhas) {
  var chaves = ordenar(no);
  for (var i = 0; i < chaves.length; i++) {
    var filho = no.filhos[chaves[i]];
    var id = prefixo + '/' + filho.nome;
    if (filho.item) {
      linhas.push(linhaItem(filho.item, nivel));
      continue;
    }
    linhas.push(linhaPacote(filho, nivel, id));
    if (!S.colapsados[id]) caminhar(filho, nivel + 1, id, linhas);
  }
}

function renderArvore() {
  if (S.busca) return;
  if (!S.itens.length) {
    $('tree').innerHTML = '<div class="empty">Carregue um <b>.jar</b> para navegar nos pacotes.</div>';
    $('tree-count').textContent = '';
    return;
  }
  var linhas = [];
  caminhar(montarArvore(S.itens), 0, '', linhas);
  $('tree-title').textContent = 'Estrutura';
  $('tree-count').textContent = S.itens.length;
  $('tree').innerHTML = linhas.join('');
  ligarArvore();
}

function ligarArvore() {
  var itens = $('tree').querySelectorAll('[data-path]');
  for (var i = 0; i < itens.length; i++) {
    itens[i].onclick = function () { abrirArquivo(this.dataset.path); setView('code'); };
  }
  var pacotes = $('tree').querySelectorAll('[data-pkg]');
  for (var p = 0; p < pacotes.length; p++) {
    pacotes[p].onclick = function () {
      var id = this.dataset.pkg;
      if (S.colapsados[id]) delete S.colapsados[id]; else S.colapsados[id] = true;
      renderArvore();
    };
  }
}

/* ---------------- abas + codigo ---------------- */
async function abrirArquivo(path, focar) {
  var item = S.indice[path];
  if (!item) return;
  if (S.abas.indexOf(path) < 0) S.abas.push(path);
  if (S.abas.length > MAX_ABAS) S.abas.shift();
  S.ativo = path;
  renderAbas();
  if (!S.busca) renderArvore();
  if (focar !== false) setView('code');

  if (item.tipo === 'bin') { mostrarBinario(item); return; }
  if (S.cache[path] !== undefined) { renderCodigo(path); return; }
  mostrarCarregando(item);
  try {
    var dados = await chamar('source', { path: path });
    S.cache[path] = dados.texto;
    if (dados.origem) item.origem = dados.origem;
    if (S.ativo === path) renderCodigo(path, dados.ms);
  } catch (e) {
    if (S.ativo === path) mostrarFalha(item, e.message);
  }
}

function renderAbas() {
  var html = '';
  for (var i = 0; i < S.abas.length; i++) {
    var p = S.abas[i];
    html += '<button class="tab" data-path="' + esc(p) + '" aria-current="' + (p === S.ativo) + '">' +
      esc(nomeArq(p)) + '<span class="x" data-close="' + esc(p) + '">&times;</span></button>';
  }
  $('tabs').innerHTML = html;
  var abas = $('tabs').querySelectorAll('.tab');
  for (var a = 0; a < abas.length; a++) abas[a].onclick = cliqueAba;
}

function cliqueAba(evento) {
  var fechar = evento.target.dataset.close;
  if (!fechar) { abrirArquivo(this.dataset.path, false); return; }
  S.abas = S.abas.filter(function (x) { return x !== fechar; });
  if (S.ativo !== fechar) { renderAbas(); return; }
  S.ativo = S.abas.length ? S.abas[S.abas.length - 1] : null;
  if (S.ativo) abrirArquivo(S.ativo, false); else limparCodigo();
}

function limparCodigo() {
  S.ativo = null;
  $('code').innerHTML = '<div class="empty">Nenhum arquivo aberto.</div>';
  $('filehead').innerHTML = '';
  $('st-file').textContent = 'nenhum arquivo aberto';
  $('st-lines').textContent = '';
  $('st-origem').textContent = '';
  renderAbas();
}

/* Classes viram FQN com ponto (br.com.x.Foo); recursos mantem o caminho do jar. */
function fqn(path) {
  var item = S.indice[path];
  var pasta = path.indexOf('/') >= 0 ? path.substring(0, path.lastIndexOf('/') + 1) : '';
  if (!item || item.tipo !== 'class') {
    return esc(pasta) + '<b>' + esc(nomeArq(path)) + '</b>';
  }
  var pacote = pasta.slice(0, -1).replace(/\//g, '.');
  var nome = nomeArq(path).replace(/\.[^.]+$/, '');
  return (pacote ? esc(pacote) + '.' : '') + '<b>' + esc(nome) + '</b>';
}

var ROTULO = {
  src: 'fonte original do jar',
  dec: 'reconstruido do bytecode',
  arq: 'recurso do jar'
};

function renderCabecalho(item, extras) {
  $('filehead').innerHTML =
    '<button class="back btn" id="btn-back-tree">&lsaquo; Estrutura</button>' +
    '<span class="fqn">' + fqn(item.path) + '</span>' +
    '<span class="chip">' + ROTULO[item.origem] + '</span>' + (extras || '') +
    '<span class="right"><button class="btn" id="btn-copy">Copiar codigo</button></span>';
  $('btn-back-tree').onclick = function () { setView('tree'); };
  $('btn-copy').onclick = copiar;
}

async function copiar() {
  var texto = S.cache[S.ativo];
  if (texto === undefined) return;
  try {
    await navigator.clipboard.writeText(texto);
    $('btn-copy').textContent = 'Copiado';
  } catch (e) {
    $('btn-copy').textContent = 'Selecione e copie';
  }
  setTimeout(function () { $('btn-copy').textContent = 'Copiar codigo'; }, 1600);
}

function mostrarCarregando(item) {
  $('filehead').innerHTML = '<span class="fqn">' + fqn(item.path) + '</span>';
  var rotulo = item.tipo === 'class' && item.origem === 'dec' ? 'Descompilando com o CFR...' : 'Lendo do jar...';
  $('code').innerHTML = '<div class="loading"><span class="spin"></span>' + rotulo + '</div>';
  $('st-file').textContent = item.path;
  $('st-lines').textContent = '';
  $('st-origem').textContent = 'processando';
}

function mostrarFalha(item, mensagem) {
  renderCabecalho(item, '');
  $('code').innerHTML = '<div class="empty"><b>' + esc(nomeArq(item.path)) + '</b><br><br>' +
    esc(mensagem) + '</div>';
  $('st-origem').textContent = 'erro';
}

function mostrarBinario(item) {
  $('filehead').innerHTML =
    '<button class="back btn" id="btn-back-tree">&lsaquo; Estrutura</button>' +
    '<span class="fqn">' + fqn(item.path) + '</span><span class="chip">binario</span>' +
    '<span class="chip">' + fmtBytes(item.tamanho) + '</span>';
  $('btn-back-tree').onclick = function () { setView('tree'); };
  $('code').innerHTML = '<div class="empty"><b>' + esc(nomeArq(item.path)) + '</b><br><br>' +
    'Recurso binario. O JVExplorer exibe apenas classes e arquivos de texto.</div>';
  $('st-file').textContent = item.path;
  $('st-lines').textContent = fmtBytes(item.tamanho);
  $('st-origem').textContent = 'binario';
}

function renderCodigo(path, ms) {
  var item = S.indice[path];
  var fonte = S.cache[path];
  var linhas = fonte.split('\n');
  renderCabecalho(item,
    '<span class="chip">' + linhas.length + ' linhas</span>' +
    (ms ? '<span class="chip">' + ms + ' ms</span>' : ''));

  var numeros = '';
  for (var i = 1; i <= linhas.length; i++) numeros += (i > 1 ? '\n' : '') + i;
  $('code').innerHTML = '<table><tr><td class="ln"><pre>' + numeros + '</pre></td>' +
    '<td><pre>' + realce(fonte, ext(path)) + '</pre></td></tr></table>';
  $('code').scrollTop = 0;

  $('st-file').textContent = path;
  $('st-lines').textContent = linhas.length + ' linhas';
  $('st-origem').textContent = ROTULO[item.origem];
}

/* ---------------- busca ---------------- */
function destacar(txt, termo) {
  var i = txt.toLowerCase().indexOf(termo);
  if (i < 0) return esc(txt);
  return esc(txt.slice(0, i)) + '<mark>' + esc(txt.slice(i, i + termo.length)) + '</mark>' +
    esc(txt.slice(i + termo.length));
}

function acharTrecho(path, termo) {
  var fonte = S.cache[path];
  if (fonte === undefined) return null;
  var linhas = fonte.split('\n');
  for (var i = 0; i < linhas.length; i++) {
    if (linhas[i].toLowerCase().indexOf(termo) >= 0) return linhas[i].trim();
  }
  return null;
}

function buscar() {
  if (!S.busca) { renderArvore(); return; }
  setView('tree');
  var termo = S.busca.toLowerCase();
  var achados = [];
  for (var i = 0; i < S.itens.length; i++) {
    var item = S.itens[i];
    var porNome = item.path.toLowerCase().indexOf(termo) >= 0;
    var trecho = porNome ? null : acharTrecho(item.path, termo);
    if (porNome || trecho) achados.push({ item: item, trecho: trecho });
  }
  $('tree-title').textContent = 'Resultados';
  $('tree-count').textContent = achados.length;
  $('tree').innerHTML = achados.length ? htmlResultados(achados, termo)
    : '<div class="empty">Nada encontrado para <b>' + esc(S.busca) + '</b>.<br>' +
      'A busca cobre nome e pacote de todos os itens, e o conteudo dos arquivos ja abertos.</div>';
  ligarResultados(achados);
}

function htmlResultados(achados, termo) {
  var html = '<div class="results">';
  for (var i = 0; i < achados.length; i++) {
    var r = achados[i];
    var detalhe = r.trecho ? destacar(r.trecho.slice(0, 110), termo)
      : destacar(r.item.path, termo);
    html += '<button class="res" data-i="' + i + '">' +
      '<div class="t1">' + destacar(nomeArq(r.item.path), termo) + '</div>' +
      '<div class="t2">' + detalhe + '</div></button>';
  }
  return html + '</div>';
}

function ligarResultados(achados) {
  var botoes = $('tree').querySelectorAll('.res');
  for (var i = 0; i < botoes.length; i++) {
    botoes[i].onclick = function () {
      abrirArquivo(achados[+this.dataset.i].item.path);
    };
  }
}

/* ---------------- diagnostico ---------------- */
function htmlDiagnostico(env) {
  var banco = env.banco || {};
  var lista = '';
  for (var i = 0; i < env.cfr.candidatos.length; i++) {
    lista += '<li><code>' + esc(env.cfr.candidatos[i]) + '</code></li>';
  }
  return '<h3>Descompilador</h3>' +
    (env.cfr.encontrado
      ? '<p>CFR localizado em <code>' + esc(env.cfr.caminho) + '</code>.</p>'
      : '<p>Nenhum <code>cfr*.jar</code> encontrado. Sem ele o JVExplorer abre os fontes ' +
        'e recursos embutidos no jar, mas nao reconstroi o bytecode das classes.</p>') +
    '<p>Caminhos verificados, nesta ordem:</p><ul>' + lista + '</ul>' +
    '<p>Para apontar manualmente, suba o WildFly com ' +
    '<code>-Djvexplorer.cfr.jar=/caminho/cfr-0.152.jar</code>.</p>' +
    '<h3>Modulos da base</h3>' +
    '<pre>usuario SUP ' + (banco.sup ? 'sim' : 'nao') +
    '\nautenticacao ' + esc(banco.auth || '?') +
    '\nusuario     ' + esc(banco.usuario || '(nao identificado)') +
    '\nconexao     ' + esc(banco.conexao || '(nao testada)') +
    '\nsessao      ' + esc((banco.sessao || []).join('\n            ') || '(vazia)') + '</pre>' +
    (banco.sup
      ? '<p>Leitura de <code>TSIMOD</code> e <code>TSIJAR</code> liberada. Para forcar um DataSource, ' +
        'suba o WildFly com <code>-Djvexplorer.ds=java:/jdbc/sankhyaDS</code>.</p>'
      : '<p>' + esc(AVISO_SUP) + ' Se o usuario logado <b>e</b> SUP e ainda aparece ' +
        '<code>nao</code>, o JSP nao conseguiu ler a identidade: <code>autenticacao</code> acima ' +
        'mostra onde procurou e <code>sessao</code> lista o que existe na sessao HTTP.</p>') +
    '<h3>Ambiente</h3><pre>tmpdir      ' + esc(env.tmpdir) +
    '\nrota API    ' + esc(baseOk || '(indefinida)') +
    '\nlimite jar  ' + env.limites.jarMb + ' MB' +
    '\nlimite zip  ' + env.limites.explodidoMb + ' MB' +
    '\nmax entradas ' + env.limites.entradas + '</pre>' +
    '<h3>Como funciona</h3>' +
    '<ul><li>O jar vem do cadastro de Modulos Java (somente leitura) ou de upload em blocos de 4 MB, ' +
    'e e gravado apenas no diretorio temporario da sessao.</li>' +
    '<li>Nenhuma tabela do Sankhya e escrita.</li>' +
    '<li>Um jar ativo por sessao: escolher outro jar recarrega e reindexa.</li>' +
    '<li>As classes sao descompiladas sob demanda, ao clicar, e o resultado fica em cache na sessao.</li>' +
    '<li>Quando a sessao expira, o diretorio temporario e apagado e o processo recomeca do zero.</li></ul>';
}

function aplicarPermissao(env) {
  var banco = env.banco || {};
  S.sup = !!banco.sup;
  $('seg-base').disabled = !S.sup;
  $('seg-base').title = S.sup ? 'Jars cadastrados em Modulos Java (TSIMOD/TSIJAR)' : AVISO_SUP;
  $('perm-aviso').hidden = S.sup;
  if (S.sup) {
    buscarModulos();
    return;
  }
  $('perm-aviso').innerHTML = '<b>Acesso restrito</b>' + esc(AVISO_SUP) +
    ' Voce esta como ' + esc(banco.usuario || 'usuario nao identificado') +
    '; o upload manual do jar segue liberado.';
  trocarOrigem('upload');
}

async function carregarEnv() {
  try {
    var env = await chamar('env');
    S.cfr = env.cfr.encontrado;
    S.env = env;
    $('dot-cfr').className = 'dot' + (S.cfr ? '' : ' off');
    $('btn-info').title = S.cfr ? 'CFR pronto: ' + env.cfr.caminho : 'CFR nao encontrado';
    aplicarPermissao(env);
    avisoCfr();
  } catch (e) {
    $('dot-cfr').className = 'dot off';
    aplicarPermissao({});
    mostrarAviso('<b>Sem comunicacao com o servidor</b>' + esc(e.message));
  }
}

/* ---------------- eventos ---------------- */
function ligarOrigem() {
  $('modlist').innerHTML = '<div class="empty">verificando acesso a base...</div>';
  $('seg-base').onclick = function () { trocarOrigem('base'); };
  $('seg-upload').onclick = function () { trocarOrigem('upload'); };
  $('q-mod').addEventListener('input', agendarBuscaModulos);
  $('q-mod').addEventListener('keydown', function (evento) {
    if (evento.key === 'Enter') { clearTimeout(S.timerMod); buscarModulos(); }
  });
}

function ligarDropzone() {
  var drop = $('drop');
  drop.onclick = function (evento) { if (evento.target.tagName !== 'LABEL') $('file').click(); };
  drop.ondragover = function (evento) { evento.preventDefault(); drop.classList.add('over'); };
  drop.ondragleave = function () { drop.classList.remove('over'); };
  drop.ondrop = function (evento) {
    evento.preventDefault();
    drop.classList.remove('over');
    if (evento.dataTransfer.files.length) enviarJar(evento.dataTransfer.files[0]);
  };
  $('file').onchange = function () {
    if (this.files.length) enviarJar(this.files[0]);
    this.value = '';
  };
}

function ligarBusca() {
  $('q').addEventListener('input', function (e) { S.busca = e.target.value.trim(); buscar(); });
  $('q').addEventListener('keydown', function (e) {
    if (e.key === 'Escape') { this.value = ''; S.busca = ''; buscar(); }
  });
  document.addEventListener('keydown', function (e) {
    if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'k' && !$('q').disabled) {
      e.preventDefault(); $('q').focus(); $('q').select();
    }
    if (e.key === 'Escape') $('overlay').hidden = true;
  });
}

/* ---------------- tema ---------------- */
var TEMA_KEY = 'jvexplorer.tema';
var TEMA_CLARO = 'light';
var TEMA_ESCURO = 'dark';

var ICO_LUA = '<path d="M20 14.5A8.5 8.5 0 0 1 9.5 4a7 7 0 1 0 10.5 10.5Z"/>';
var ICO_SOL = '<circle cx="12" cy="12" r="4"/>' +
  '<path d="M12 3v2m0 14v2M3 12h2m14 0h2M5.6 5.6 7 7m10 10 1.4 1.4M18.4 5.6 17 7M7 17l-1.4 1.4"/>';

function temaAtual() {
  return document.documentElement.getAttribute('data-theme') === TEMA_CLARO ? TEMA_CLARO : TEMA_ESCURO;
}

function aplicarTema(tema) {
  var claro = tema === TEMA_CLARO;
  var raiz = document.documentElement;

  if (claro) raiz.setAttribute('data-theme', TEMA_CLARO);
  else raiz.removeAttribute('data-theme');

  var botao = $('btn-tema');
  botao.setAttribute('aria-pressed', claro ? 'true' : 'false');
  botao.setAttribute('aria-label', claro ? 'Ativar modo escuro' : 'Ativar modo claro');
  botao.title = claro ? 'Modo claro ativo - clique para o escuro' : 'Modo escuro ativo - clique para o claro';
  $('ico-tema').innerHTML = claro ? ICO_SOL : ICO_LUA;

  try { window.localStorage.setItem(TEMA_KEY, claro ? TEMA_CLARO : TEMA_ESCURO); }
  catch (e) { /* storage indisponivel: tema vale so para esta sessao */ }
}

function ligarTema() {
  aplicarTema(temaAtual());
  $('btn-tema').onclick = function () {
    aplicarTema(temaAtual() === TEMA_CLARO ? TEMA_ESCURO : TEMA_CLARO);
  };
}

/* Com jar aberto o Diagnostico abre na analise; sem jar so o ambiente faz sentido. */
function abrirDiagnostico() {
  $('overlay').hidden = false;
  mostrarAbaModal(S.jar ? 'analise' : 'ambiente');
}

function mostrarAbaModal(aba) {
  $('modal').classList.toggle('largo', aba === 'analise');
  $('modal-abas').innerHTML =
    '<button class="segb' + (aba === 'analise' ? ' on' : '') + '" type="button" id="aba-analise"' +
      (S.jar ? '' : ' disabled title="Abra um jar para analisar"') + '>Analise do jar</button>' +
    '<button class="segb' + (aba === 'ambiente' ? ' on' : '') + '" type="button" id="aba-ambiente">Ambiente</button>';
  $('aba-analise').onclick = function () { mostrarAbaModal('analise'); };
  $('aba-ambiente').onclick = function () { mostrarAbaModal('ambiente'); };
  if (aba === 'analise') { carregarAnalise(); return; }
  $('modal-body').innerHTML = S.env ? htmlDiagnostico(S.env)
    : '<p>Diagnostico indisponivel: o servidor nao respondeu.</p>';
}

/* ---------------- analise do jar ---------------- */
var MAX_ANALISE = 300;

/* Frases montadas so com fatos lidos do bytecode, nada e inferido alem disso. */
var PAPEL_FRASE = {
  'Evento programavel': 'Evento programavel: reage a inclusao, alteracao ou exclusao de registros.',
  'Botao de acao': 'Botao de acao: executa uma rotina sob demanda a partir de uma tela.',
  'Acao agendada': 'Acao agendada: executada periodicamente pelo agendador do Sankhya.',
  'Regra de negocio': 'Regra de negocio: valida ou complementa operacoes do sistema.',
  'Botao de acao (addon)': 'Botao de acao do Addon Studio: executa uma rotina sob demanda a partir de uma tela.',
  'Listener (addon)': 'Listener do Addon Studio: reage a eventos de persistencia de uma entidade.',
  'Job (addon)': 'Job do Addon Studio: executado periodicamente pelo agendador.',
  'Regra de negocio (addon)': 'Regra de negocio do Addon Studio: valida ou complementa operacoes do sistema.',
  'Callback (addon)': 'Callback do Addon Studio: chamado pelo sistema em um ponto especifico do fluxo.',
  'EJB': 'EJB: servico de backend publicado no servidor de aplicacao.'
};

async function carregarAnalise() {
  if (S.analise) { renderAnalise(); return; }
  var jar = S.jar;
  $('modal-body').innerHTML = '<div class="empty">Analisando as classes do jar...</div>';
  try {
    var dados = await chamar('analise');
    if (S.jar !== jar) return;
    S.analise = dados;
    if (!$('overlay').hidden && $('aba-analise').classList.contains('on')) renderAnalise();
  } catch (e) {
    $('modal-body').innerHTML = '<p>Falha na analise: ' + esc(e.message) + '</p>';
  }
}

function renderAnalise() {
  $('modal-body').innerHTML = htmlResumoAnalise(S.analise.resumo) +
    '<h3>Classes</h3>' +
    '<div class="minisearch"><input id="q-analise" type="search" autocomplete="off" spellcheck="false"' +
    ' placeholder="Filtrar por classe, papel, tabela ou entidade..."></div>' +
    '<div id="lista-analise"></div>';
  $('q-analise').addEventListener('input', function (e) { renderListaAnalise(e.target.value.trim()); });
  renderListaAnalise('');
}

function htmlResumoAnalise(r) {
  var papeis = Object.keys(r.papeis).map(function (p) {
    return '<span class="pill' + (p === 'Apoio' ? '' : ' forte') + '">' + esc(p) + ' <b>' + r.papeis[p] + '</b></span>';
  }).join('');
  return '<h3>Resumo</h3>' +
    '<p>' + r.classes + ' classes analisadas' + (r.falhas ? ', ' + r.falhas + ' arquivo(s) .class ilegivel(is)' : '') +
    '. Leitura direta do bytecode, sem executar nada: papel vem da heranca e das anotacoes; ' +
    'tabelas e entidades sao inferidas dos textos SQL e literais da classe.</p>' +
    '<div class="pills">' + papeis + '</div>' +
    htmlTabelasAnalise(r.tabelas);
}

function htmlTabelasAnalise(tabelas) {
  if (!tabelas.length) return '<p>Nenhuma tabela identificada em SQL literal.</p>';
  var linhas = tabelas.map(function (t) {
    return '<tr><td><code>' + esc(t.nome) + '</code></td><td>' + t.leitura + '</td><td>' + t.escrita + '</td></tr>';
  }).join('');
  return '<h3>Tabelas citadas</h3><div class="tabwrap"><table class="tab-analise"><thead><tr>' +
    '<th>Tabela</th><th>Classes que leem</th><th>Classes que gravam</th></tr></thead>' +
    '<tbody>' + linhas + '</tbody></table></div>';
}

function textoBuscaClasse(c) {
  return [c.path, c.papel].concat(c.leitura, c.escrita, c.entidades).join(' ').toLowerCase();
}

function renderListaAnalise(termo) {
  var t = termo.toLowerCase();
  var achados = S.analise.classes.filter(function (c) { return !t || textoBuscaClasse(c).indexOf(t) >= 0; });
  // Ordena por pacote antes do corte para o limite nao deixar pacotes pela metade.
  achados.sort(function (a, b) { return pacoteDe(a.path).localeCompare(pacoteDe(b.path)); });
  var grupos = agruparPorPacote(achados.slice(0, MAX_ANALISE));
  var aberto = Boolean(t) || grupos.length === 1;
  var html = grupos.map(function (g) { return htmlPacoteAnalise(g, aberto); }).join('');
  if (achados.length > MAX_ANALISE) {
    html += '<p class="mais">Exibindo ' + MAX_ANALISE + ' de ' + achados.length + ' classes. Refine o filtro.</p>';
  }
  $('lista-analise').innerHTML = html || '<div class="empty">Nenhuma classe corresponde ao filtro.</div>';
  ligarListaAnalise();
}

function pacoteDe(path) {
  var corte = path.lastIndexOf('/');
  return corte < 0 ? '(pacote padrao)' : path.substring(0, corte).replace(/\//g, '.');
}

/* Pacotes em ordem alfabetica; dentro de cada um vale a ordem do servidor (entradas primeiro). */
function agruparPorPacote(classes) {
  var grupos = {};
  classes.forEach(function (c) {
    var pacote = pacoteDe(c.path);
    (grupos[pacote] = grupos[pacote] || []).push(c);
  });
  return Object.keys(grupos).sort(function (a, b) { return a.localeCompare(b); }).map(function (p) { return { nome: p, classes: grupos[p] }; });
}

function htmlPacoteAnalise(grupo, aberto) {
  var entradas = grupo.classes.filter(function (c) { return c.papel !== 'Apoio'; }).length;
  return '<details class="pkg-analise"' + (aberto ? ' open' : '') + '><summary>' +
      '<code>' + esc(grupo.nome) + '</code>' +
      (entradas ? '<span class="pill forte">' + entradas + ' entrada(s)</span>' : '') +
      '<span class="pill">' + grupo.classes.length + ' classe(s)</span></summary>' +
    '<div class="pkg-classes">' + grupo.classes.map(htmlClasseAnalise).join('') + '</div>' +
  '</details>';
}

function linhaFicha(rotulo, itens) {
  if (!itens || !itens.length) return '';
  return '<dt>' + rotulo + '</dt><dd>' + itens.map(esc).join(', ') + '</dd>';
}

function htmlClasseAnalise(c) {
  var herda = c.super && c.super !== 'java.lang.Object' ? [c.super] : [];
  return '<details class="cls-analise"><summary>' +
      '<span class="pill' + (c.papel === 'Apoio' ? '' : ' forte') + '">' + esc(c.papel) + '</span>' +
      '<code><b>' + esc(nomeArq(c.path).replace(/\.[^.]+$/, '')) + '</b></code></summary>' +
    '<p>' + esc(descreverClasse(c)) + '</p>' +
    '<dl class="ficha">' +
      linhaFicha('Herda de', herda) + linhaFicha('Implementa', c.interfaces) +
      linhaFicha('Le', c.leitura) + linhaFicha('Grava', c.escrita) +
      linhaFicha('Entidades provaveis', c.entidades) + linhaFicha('APIs Sankhya', c.apis) +
      linhaFicha('Metodos publicos', c.metodos) + linhaFicha('Usa do jar', c.dependencias) +
    '</dl>' +
    '<button class="btn" type="button" data-path="' + esc(c.path) + '">Abrir codigo</button>' +
  '</details>';
}

function descreverClasse(c) {
  var partes = [PAPEL_FRASE[c.papel] || 'Classe de apoio, usada por outras classes do jar.'];
  if (c.leitura.length) partes.push('Consulta ' + c.leitura.join(', ') + '.');
  else if (c.leApi) partes.push('Le dados via API JAPE/JDBC.');
  if (c.escrita.length) partes.push('Grava em ' + c.escrita.join(', ') + '.');
  else if (c.gravaApi) partes.push('Grava dados via API JAPE/JDBC.');
  if (c.entidades.length) partes.push('Provavelmente opera as entidades ' + c.entidades.join(', ') + '.');
  if (c.dependencias.length) partes.push('Depende de ' + c.dependencias.length + ' classe(s) do proprio jar.');
  return partes.join(' ');
}

function ligarListaAnalise() {
  var botoes = $('lista-analise').querySelectorAll('button[data-path]');
  for (var i = 0; i < botoes.length; i++) {
    botoes[i].onclick = function () {
      $('overlay').hidden = true;
      abrirArquivo(this.dataset.path);
    };
  }
}

function ligarModal() {
  $('btn-info').onclick = abrirDiagnostico;
  $('btn-close').onclick = function () { $('overlay').hidden = true; };
  $('overlay').onclick = function (e) { if (e.target === $('overlay')) $('overlay').hidden = true; };
}

/* Oculta a barra de titulo e o botao de configuracao do gadget GWT. */
function ocultarBarraSankhya() {
  try {
    var estilo = parent.document.createElement('style');
    estilo.textContent = '.VCompactBar, .DashWindow-TopBar-Title { display: none !important; } ' +
      '.gwt-Button.chartConfigButton { display: none !important; }';
    parent.document.head.appendChild(estilo);
  } catch (e) { /* cross-origin: ignora */ }
}

function init() {
  ocultarBarraSankhya();
  ligarTema();
  ligarOrigem();
  ligarDropzone();
  ligarBusca();
  ligarModal();
  $('back-jar').onclick = function () { setView('jar'); };
  window.addEventListener('resize', function () { if (!isMobile()) $('app').dataset.view = ''; });
  if (!isMobile()) $('app').dataset.view = '';
  renderArvore();
  limparCodigo();
  carregarEnv();
}

window.enviarJar = enviarJar;
window.resetar = resetar;
init();
</script>
</body>
</html>
<%
    return;
}

/* Binario: resolvido antes do content-type JSON. pushBody isola o JspWriter,
   senao o flush final do JSP colide com getOutputStream(). */
if ("download".equals(acao)) {
    Estado atual = estado(session);
    if (!atual.jar.isFile()) {
        response.sendError(HttpServletResponse.SC_NOT_FOUND, "Nenhum jar carregado nesta sessao.");
        return;
    }
    out.clear();
    out = pageContext.pushBody();
    enviarJar(atual, response);
    return;
}

/* ========================= API JSON (?action=...) ========================= */
response.setContentType("application/json;charset=UTF-8");
response.setHeader("Cache-Control", "no-cache, no-store, must-revalidate");
response.setHeader("Pragma", "no-cache");

try {
    Estado st = estado(session);

    if ("env".equals(acao)) {
        File cfr = acharCfr(application, request);
        StringBuilder sb = new StringBuilder(512);
        sb.append("{\"success\":true,\"cfr\":{\"encontrado\":").append(cfr != null)
          .append(",\"caminho\":\"").append(cfr == null ? "" : escapeJson(cfr.getAbsolutePath()))
          .append("\",\"candidatos\":[");
        List<String> candidatos = candidatosCfr(application, request);
        for (int i = 0; i < candidatos.size(); i++) {
            if (i > 0) sb.append(',');
            sb.append('"').append(escapeJson(candidatos.get(i))).append('"');
        }
        sb.append("]},\"banco\":").append(jsonBanco(session))
          .append(",\"tmpdir\":\"").append(escapeJson(System.getProperty("java.io.tmpdir")))
          .append("\",\"limites\":{\"jarMb\":").append(MAX_JAR / 1048576L)
          .append(",\"explodidoMb\":").append(MAX_EXPLODIDO / 1048576L)
          .append(",\"entradas\":").append(MAX_ENTRADAS).append("}}");
        out.print(sb.toString());

    } else if ("probe".equals(acao)) {
        InputStream corpo = request.getInputStream();
        byte[] descarte = new byte[BUFFER];
        while (corpo.read(descarte) != -1) { /* consome e descarta */ }
        out.print("{\"success\":true,\"probe\":true}");

    } else if ("modulos".equals(acao)) {
        exigirSup(session);
        out.print(jsonModulos(request.getParameter("q")));

    } else if ("jars".equals(acao)) {
        exigirSup(session);
        out.print(jsonJars(inteiro(request.getParameter("mod"))));

    } else if ("abrir".equals(acao)) {
        exigirSup(session);
        abrirDaBase(st, inteiro(request.getParameter("mod")), inteiro(request.getParameter("jar")));
        out.print("{\"success\":true,\"jar\":" + jsonJar(st) + ",\"itens\":" + jsonItens(st) + "}");

    } else if ("analise".equals(acao)) {
        out.print(jsonAnalise(st));

    } else if ("reset".equals(acao)) {
        limpar(st);
        session.removeAttribute(SESS);
        out.print("{\"success\":true}");

    } else if ("upload".equals(acao)) {
        int bloco = Integer.parseInt(request.getParameter("chunk"));
        boolean ultimo = "1".equals(request.getParameter("final"));
        if (bloco == 0) limpar(st);
        st.dir.mkdirs();
        anexar(st.parcial, request.getInputStream(), st.parcial.exists() ? st.parcial.length() : 0L);

        if (!ultimo) {
            out.print("{\"success\":true,\"parcial\":true,\"recebido\":" + st.parcial.length() + "}");
        } else {
            validarAssinatura(st.parcial);
            apagar(st.jar);
            if (!st.parcial.renameTo(st.jar)) throw new IOException("Nao foi possivel finalizar o upload.");
            String enviado = request.getParameter("nome");
            st.nomeJar = (enviado == null || enviado.trim().length() == 0)
                       ? "arquivo.jar" : nomeSimples(enviado.replace('\\', '/'));
            st.tamanhoJar = st.jar.length();
            indexar(st, extrairTudo(st));
            out.print("{\"success\":true,\"jar\":" + jsonJar(st) + ",\"itens\":" + jsonItens(st) + "}");
        }

    } else if ("source".equals(acao)) {
        String path = request.getParameter("path");
        No no = path == null ? null : st.indice.get(path);
        if (no == null) {
            out.print(jsonErro("Item nao encontrado nesta sessao. Recarregue o jar."));
        } else if ("bin".equals(no.tipo)) {
            out.print(jsonErro("Recurso binario: o JVExplorer nao exibe este tipo de arquivo."));
        } else {
            long inicio = System.currentTimeMillis();
            String texto = st.cache.get(path);
            if (texto == null) {
                if (no.arquivo != null && no.arquivo.isFile()) {
                    texto = lerTexto(no.arquivo);
                } else {
                    File cfr = acharCfr(application, request);
                    if (cfr == null) throw new IOException(
                        "Descompilador nao encontrado no servidor. Abra Diagnostico para ver os caminhos verificados.");
                    texto = descompilar(st, no, cfr);
                }
                if (st.cache.size() > 400) st.cache.clear();
                st.cache.put(path, texto);
            }
            out.print("{\"success\":true,\"path\":\"" + escapeJson(path)
                    + "\",\"origem\":\"" + no.origem
                    + "\",\"ms\":" + (System.currentTimeMillis() - inicio)
                    + ",\"texto\":\"" + escapeJson(texto) + "\"}");
        }

    } else {
        out.print(jsonErro("Acao desconhecida: " + acao));
    }

} catch (Throwable falha) {
    out.print(jsonErro(descrever(falha.getCause() == null ? falha : falha.getCause())));
}
%>
