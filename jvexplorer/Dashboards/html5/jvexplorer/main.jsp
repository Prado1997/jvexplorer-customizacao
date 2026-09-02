<%@ page language="java" contentType="text/html; charset=UTF-8" pageEncoding="UTF-8" session="true" trimDirectiveWhitespaces="true"%>
<%@ page import="java.io.*"%>
<%@ page import="java.net.*"%>
<%@ page import="java.nio.*"%>
<%@ page import="java.nio.charset.*"%>
<%@ page import="java.util.*"%>
<%@ page import="java.util.jar.*"%>
<%@ page import="javax.servlet.*"%>
<%@ page import="javax.servlet.http.*"%>
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
    long tamanhoJar;
    int qtdClasses;
    int qtdEntradas;
    int seq;
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
        while ((lidos = in.read(buf)) > 0) bos.write(buf, 0, lidos);
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

private static synchronized Estado estado(HttpSession sessao) {
    Estado atual = (Estado) sessao.getAttribute(SESS);
    if (atual != null) return atual;
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
    estado.nomeJar = "";
    estado.tamanhoJar = 0;
    estado.qtdClasses = 0;
    estado.qtdEntradas = 0;
}

/* --------------------------------------------------------------- upload */

private static void anexar(File destino, InputStream in, long jaGravado) throws IOException {
    OutputStream out = new BufferedOutputStream(new FileOutputStream(destino, true));
    long total = jaGravado;
    try {
        byte[] buf = new byte[BUFFER];
        int lidos;
        while ((lidos = in.read(buf)) > 0) {
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
        while ((lidos = in.read(buf)) > 0) {
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

private static List<String> candidatosCfr(ServletContext contexto, HttpServletRequest requisicao) {
    List<String> candidatos = new ArrayList<String>();
    String propriedade = System.getProperty("jvexplorer.cfr.jar");
    if (propriedade != null && propriedade.trim().length() > 0) candidatos.add(propriedade.trim());
    String meuPath = requisicao.getServletPath();
    if (meuPath != null && meuPath.lastIndexOf('/') > 0) {
        String pasta = meuPath.substring(0, meuPath.lastIndexOf('/'));
        String real = contexto.getRealPath(pasta + "/lib");
        if (real != null) candidatos.add(real);
        String realPasta = contexto.getRealPath(pasta);
        if (realPasta != null) candidatos.add(realPasta);
    }
    String raiz = contexto.getRealPath("/dashboard");
    if (raiz != null) candidatos.add(raiz);
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
        .append("\",\"tamanho\":").append(estado.tamanhoJar)
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
    String urlJsp = request.getServletPath();
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
  --shadow:0 1px 2px rgba(0,0,0,.4), 0 8px 24px rgba(0,0,0,.35);
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
.jarcard .acoes{display:flex;gap:7px;margin-top:11px}

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
.overlay{position:fixed;inset:0;background:rgba(6,8,12,.66);display:grid;place-items:center;padding:24px;z-index:50}
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
  .back{display:inline-flex;align-items:center;gap:5px}
  .brand span{display:none}
  .kbd{display:none}
}
@media (prefers-reduced-motion:reduce){*{transition:none!important;animation:none!important}}
</style>
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
    </div>
  </header>

  <div class="panes">

    <section class="pane p-jar">
      <div class="pane-head">Arquivo <span class="count" id="jar-count"></span></div>
      <div class="scroll">
        <div class="jarpane">
          <div class="drop" id="drop">
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
  <div class="modal" role="dialog" aria-modal="true" aria-labelledby="mtitle">
    <div class="modal-head">
      <h2 id="mtitle">Diagnostico do JVExplorer</h2>
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
  cfr: false
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

async function enviarJar(arquivo) {
  if (!/\.(jar|zip)$/i.test(arquivo.name)) { erro('Selecione um arquivo .jar.'); return; }
  $('aviso').hidden = S.cfr;
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
}

function aplicarJar(resposta) {
  S.jar = resposta.jar;
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
  S.jar = null; S.itens = []; S.indice = {}; S.cache = {};
  S.abas = []; S.ativo = null; S.busca = '';
  $('q').value = ''; $('q').disabled = true;
  $('jar-info').hidden = true;
  $('jar-count').textContent = '';
  $('tree').innerHTML = '<div class="empty">Carregue um <b>.jar</b> para navegar nos pacotes.</div>';
  $('tree-count').textContent = '';
  $('st-jar').textContent = 'nenhum jar carregado';
  limparCodigo();
  setView('jar');
}

function renderJarInfo() {
  $('jar-count').textContent = S.jar.classes;
  $('jar-info').hidden = false;
  $('jar-info').innerHTML =
    '<div class="nm">' + esc(S.jar.nome) + '</div>' +
    '<dl>' +
      '<dt>Tamanho</dt><dd>' + fmtBytes(S.jar.tamanho) + '</dd>' +
      '<dt>Entradas</dt><dd>' + S.jar.entradas + '</dd>' +
      '<dt>Classes</dt><dd>' + S.jar.classes + '</dd>' +
      '<dt>Navegaveis</dt><dd>' + S.jar.itens + '</dd>' +
    '</dl>' +
    '<div class="acoes">' +
      '<button class="btn" id="btn-trocar">Trocar jar</button>' +
      '<button class="btn danger" id="btn-reset">Descartar</button>' +
    '</div>';
  $('btn-trocar').onclick = function () { $('file').click(); };
  $('btn-reset').onclick = resetar;
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
    '<h3>Ambiente</h3><pre>tmpdir      ' + esc(env.tmpdir) +
    '\nrota API    ' + esc(baseOk || '(indefinida)') +
    '\nlimite jar  ' + env.limites.jarMb + ' MB' +
    '\nlimite zip  ' + env.limites.explodidoMb + ' MB' +
    '\nmax entradas ' + env.limites.entradas + '</pre>' +
    '<h3>Como funciona</h3>' +
    '<ul><li>O jar e enviado em blocos de 4 MB e gravado apenas no diretorio temporario da sessao.</li>' +
    '<li>Nenhuma tabela do Sankhya e lida ou escrita.</li>' +
    '<li>As classes sao descompiladas sob demanda, ao clicar, e o resultado fica em cache na sessao.</li>' +
    '<li>Quando a sessao expira, o diretorio temporario e apagado e o processo recomeca do zero.</li></ul>';
}

async function carregarEnv() {
  try {
    var env = await chamar('env');
    S.cfr = env.cfr.encontrado;
    S.env = env;
    $('dot-cfr').className = 'dot' + (S.cfr ? '' : ' off');
    $('btn-info').title = S.cfr ? 'CFR pronto: ' + env.cfr.caminho : 'CFR nao encontrado';
    if (!S.cfr) {
      mostrarAviso('<b>Descompilador ausente</b>Nenhum <code>cfr*.jar</code> foi encontrado no servidor. ' +
        'Fontes e recursos embutidos no jar continuam abrindo; classes sem fonte nao. ' +
        'Veja <b>Diagnostico</b>.');
    }
  } catch (e) {
    $('dot-cfr').className = 'dot off';
    mostrarAviso('<b>Sem comunicacao com o servidor</b>' + esc(e.message));
  }
}

/* ---------------- eventos ---------------- */
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

function ligarModal() {
  $('btn-info').onclick = function () {
    $('modal-body').innerHTML = S.env ? htmlDiagnostico(S.env)
      : '<p>Diagnostico indisponivel: o servidor nao respondeu.</p>';
    $('overlay').hidden = false;
  };
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
        sb.append("]},\"tmpdir\":\"").append(escapeJson(System.getProperty("java.io.tmpdir")))
          .append("\",\"limites\":{\"jarMb\":").append(MAX_JAR / 1048576L)
          .append(",\"explodidoMb\":").append(MAX_EXPLODIDO / 1048576L)
          .append(",\"entradas\":").append(MAX_ENTRADAS).append("}}");
        out.print(sb.toString());

    } else if ("probe".equals(acao)) {
        InputStream corpo = request.getInputStream();
        byte[] descarte = new byte[BUFFER];
        while (corpo.read(descarte) > 0) { /* consome e descarta */ }
        out.print("{\"success\":true,\"probe\":true}");

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
    Throwable raiz = falha.getCause() == null ? falha : falha.getCause();
    String mensagem = raiz.getMessage();
    out.print(jsonErro(mensagem == null || mensagem.length() == 0
        ? raiz.getClass().getName() : mensagem));
}
%>
