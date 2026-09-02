package br.com.sankhya.dstech.utils;

import br.com.sankhya.ws.ServiceContext;

public class MessageUtils {

    public static void showInfo(String message) {
        ServiceContext ctx = ServiceContext.getCurrent();
        if (ctx == null) {
            System.out.println("ServiceContext não inicializado abortando showInfo");
            return;
        }

        ctx.setStatus(2);
        ctx.setStatusMessage(message);
    }
}