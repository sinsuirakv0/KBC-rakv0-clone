import java.awt.Graphics2D;
import java.awt.RenderingHints;
import java.awt.image.BufferedImage;
import java.io.File;
import java.io.IOException;
import java.nio.file.AtomicMoveNotSupportedException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import javax.imageio.ImageIO;

public final class IconResizer {
    private static final double ADAPTIVE_FOREGROUND_SCALE = 2.0 / 3.0;

    private IconResizer() {
    }

    public static void main(String[] arguments) throws IOException {
        if (arguments.length < 2) {
            throw new IllegalArgumentException("source PNG and one or more target PNG files are required");
        }

        BufferedImage sourceImage = ImageIO.read(new File(arguments[0]));
        if (sourceImage == null || sourceImage.getWidth() <= 0 || sourceImage.getHeight() <= 0) {
            throw new IOException("source image is not a readable PNG");
        }

        for (int index = 1; index < arguments.length; index += 1) {
            resizeToTarget(sourceImage, Path.of(arguments[index]));
        }
    }

    private static void resizeToTarget(BufferedImage sourceImage, Path targetPath) throws IOException {
        BufferedImage targetImage = ImageIO.read(targetPath.toFile());
        if (targetImage == null || targetImage.getWidth() <= 0 || targetImage.getHeight() <= 0) {
            throw new IOException("target image is not a readable PNG: " + targetPath);
        }

        int targetWidth = targetImage.getWidth();
        int targetHeight = targetImage.getHeight();
        BufferedImage outputImage = new BufferedImage(targetWidth, targetHeight, BufferedImage.TYPE_INT_ARGB);
        double scale = Math.min(
            (double) targetWidth / sourceImage.getWidth(),
            (double) targetHeight / sourceImage.getHeight()
        );
        if (isAdaptiveForeground(targetPath)) {
            scale *= ADAPTIVE_FOREGROUND_SCALE;
        }
        int outputWidth = Math.max(1, (int) Math.round(sourceImage.getWidth() * scale));
        int outputHeight = Math.max(1, (int) Math.round(sourceImage.getHeight() * scale));
        int offsetX = (targetWidth - outputWidth) / 2;
        int offsetY = (targetHeight - outputHeight) / 2;

        Graphics2D graphics = outputImage.createGraphics();
        try {
            graphics.setRenderingHint(
                RenderingHints.KEY_INTERPOLATION,
                RenderingHints.VALUE_INTERPOLATION_BICUBIC
            );
            graphics.setRenderingHint(
                RenderingHints.KEY_RENDERING,
                RenderingHints.VALUE_RENDER_QUALITY
            );
            graphics.setRenderingHint(
                RenderingHints.KEY_ALPHA_INTERPOLATION,
                RenderingHints.VALUE_ALPHA_INTERPOLATION_QUALITY
            );
            graphics.drawImage(sourceImage, offsetX, offsetY, outputWidth, outputHeight, null);
        } finally {
            graphics.dispose();
        }

        Path absoluteTarget = targetPath.toAbsolutePath();
        Path temporaryPath = Files.createTempFile(absoluteTarget.getParent(), ".kbc-icon-", ".png");
        try {
            if (!ImageIO.write(outputImage, "png", temporaryPath.toFile())) {
                throw new IOException("PNG writer is unavailable");
            }
            try {
                Files.move(
                    temporaryPath,
                    absoluteTarget,
                    StandardCopyOption.ATOMIC_MOVE,
                    StandardCopyOption.REPLACE_EXISTING
                );
            } catch (AtomicMoveNotSupportedException exception) {
                Files.move(temporaryPath, absoluteTarget, StandardCopyOption.REPLACE_EXISTING);
            }
        } finally {
            Files.deleteIfExists(temporaryPath);
        }
    }

    private static boolean isAdaptiveForeground(Path targetPath) {
        Path fileName = targetPath.getFileName();
        return fileName != null && "icon_foreground.png".equals(fileName.toString());
    }
}
